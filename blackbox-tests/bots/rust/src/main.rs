//! rnatch echo bot for blackbox performance testing.
//!
//! Connects as an XMPP component and echoes all received stanzas.
//! Also bridges RabbitMQ, Kafka, and SQS request/response queues.
//!
//! Usage:
//!   rnatch-echo-bot --xmpp-comp            # XMPP component only
//!   rnatch-echo-bot --xmpp-comp --rabbitmq # XMPP + RabbitMQ
//!   rnatch-echo-bot --all                  # all transports

use std::sync::Arc;
use std::time::{SystemTime, UNIX_EPOCH};

use async_trait::async_trait;
use clap::Parser;
use tokio::signal;
use tokio::sync::Mutex;
use tracing::{error, info};

use rnatch::claws::Claw;
use rnatch::snatch::{Snatch, SnatchHandler, SnatchInfo, SnatchState};
use rnatch::Result;

#[derive(Parser, Debug)]
#[command(name = "rnatch-echo-bot", about = "Echo bot for blackbox testing")]
struct Args {
    /// Enable XMPP component transport
    #[arg(long, default_value_t = false)]
    xmpp_comp: bool,

    /// XMPP component host
    #[arg(long, default_value = "localhost")]
    xmpp_host: String,

    /// XMPP component port
    #[arg(long, default_value_t = 5275)]
    xmpp_port: u16,

    /// XMPP component domain
    #[arg(long, default_value = "echo.localhost")]
    xmpp_domain: String,

    /// XMPP component password
    #[arg(long, default_value = "secret")]
    xmpp_password: String,

    /// Enable RabbitMQ transport
    #[arg(long, default_value_t = false)]
    rabbitmq: bool,

    /// RabbitMQ host
    #[arg(long, default_value = "localhost")]
    rabbitmq_host: String,

    /// RabbitMQ port
    #[arg(long, default_value_t = 5672)]
    rabbitmq_port: u16,

    /// Enable Kafka transport
    #[arg(long, default_value_t = false)]
    kafka: bool,

    /// Kafka bootstrap servers
    #[arg(long, default_value = "localhost:9092")]
    kafka_bootstrap: String,

    /// Enable SQS transport
    #[arg(long, default_value_t = false)]
    sqs: bool,

    /// SQS/LocalStack endpoint
    #[arg(long, default_value = "http://localhost:4566")]
    sqs_endpoint: String,

    /// Enable all transports
    #[arg(long, default_value_t = false)]
    all: bool,
}

/// Echo handler: for XMPP, echoes received stanzas with from/to swapped.
struct EchoHandler {
    xmpp_comp: Option<Arc<rnatch::claws::xmpp_comp::ClawsXmppComp>>,
    xmpp_buffer: Mutex<String>,
    xmpp_domain: String,
}

#[async_trait]
impl SnatchHandler for EchoHandler {
    fn init(&self) -> Result<SnatchState> {
        Ok(SnatchState::new(()))
    }

    async fn handle_info(&self, info: SnatchInfo, _state: &mut SnatchState) -> Result<()> {
        match info {
            SnatchInfo::Connected(claw) => {
                info!("Claw connected: {}", claw);
            }
            SnatchInfo::Disconnected(claw) => {
                info!("Claw disconnected: {}", claw);
            }
            SnatchInfo::ReceivedWithVia(data, via) => {
                let raw = String::from_utf8_lossy(&data);

                if via.claws == "xmpp_comp" {
                    // XMPP over TCP is a stream; reads may contain partial or multiple stanzas.
                    // Buffer and only echo complete message/iq stanzas.
                    let stanzas = {
                        let mut buf = self.xmpp_buffer.lock().await;
                        buf.push_str(&raw);
                        take_complete_stanzas(&mut buf)
                    };
                    if let Some(ref comp) = self.xmpp_comp {
                        for stanza in stanzas {
                            if !should_echo_stanza(&stanza, &self.xmpp_domain) {
                                continue;
                            }
                            let echoed = swap_from_to(&stanza);
                            if let Err(e) = comp.send(echoed.as_bytes(), "").await {
                                error!("Failed to send echo: {}", e);
                            }
                        }
                    }
                }
            }
            SnatchInfo::Received(data) => {
                let raw = String::from_utf8_lossy(&data);
                info!("Received (no via): {} bytes", raw.len());
            }
        }
        Ok(())
    }
}

/// Swap `from` and `to` attributes in an XML stanza string.
/// Also changes type="get" to type="result" for IQ stanzas.
fn swap_from_to(xml: &str) -> String {
    // Extract from and to values
    let from_val = extract_attr(xml, "from");
    let to_val = extract_attr(xml, "to");

    let mut result = xml.to_string();

    if let (Some(from), Some(to)) = (from_val, to_val) {
        // Replace from with to's value and vice versa
        // Use placeholder to avoid double-replacement
        result = result.replacen(&format!("from=\"{}\"", from), "from=\"__PLACEHOLDER_TO__\"", 1);
        result = result.replacen(&format!("to=\"{}\"", to), &format!("to=\"{}\"", from), 1);
        result = result.replace("from=\"__PLACEHOLDER_TO__\"", &format!("from=\"{}\"", to));

        // Same for single-quoted attributes
        if result == xml.to_string() {
            result = result.replacen(&format!("from='{}'", from), "from='__PLACEHOLDER_TO__'", 1);
            result = result.replacen(&format!("to='{}'", to), &format!("to='{}'", from), 1);
            result = result.replace("from='__PLACEHOLDER_TO__'", &format!("from='{}'", to));
        }
    }

    // For IQ get -> result
    if result.contains("<iq ") && result.contains("type=\"get\"") {
        result = result.replace("type=\"get\"", "type=\"result\"");
    }
    if result.contains("<iq ") && result.contains("type='get'") {
        result = result.replace("type='get'", "type='result'");
    }

    result
}

fn extract_attr(xml: &str, attr: &str) -> Option<String> {
    for quote in ['"', '\''] {
        let pattern = format!("{}={}", attr, quote);
        if let Some(start) = xml.find(&pattern) {
            let value_start = start + pattern.len();
            if let Some(end) = xml[value_start..].find(quote) {
                return Some(xml[value_start..value_start + end].to_string());
            }
        }
    }
    None
}

fn take_complete_stanzas(buffer: &mut String) -> Vec<String> {
    let mut out = Vec::new();
    loop {
        let msg_pos = buffer.find("<message");
        let iq_pos = buffer.find("<iq");
        let start = match (msg_pos, iq_pos) {
            (Some(m), Some(i)) => m.min(i),
            (Some(m), None) => m,
            (None, Some(i)) => i,
            (None, None) => {
                // Keep a small tail if no stanza start is found yet.
                if buffer.len() > 4096 {
                    let tail = buffer.split_off(buffer.len() - 1024);
                    *buffer = tail;
                }
                break;
            }
        };

        if start > 0 {
            buffer.drain(..start);
        }

        if buffer.starts_with("<message") {
            if let Some(end_rel) = buffer.find("</message>") {
                let end = end_rel + "</message>".len();
                out.push(buffer[..end].to_string());
                buffer.drain(..end);
                continue;
            }
            break;
        }

        if buffer.starts_with("<iq") {
            if let Some(end_rel) = buffer.find("</iq>") {
                let end = end_rel + "</iq>".len();
                out.push(buffer[..end].to_string());
                buffer.drain(..end);
                continue;
            }
            break;
        }

        buffer.drain(..1);
    }
    out
}

fn should_echo_stanza(stanza: &str, component_domain: &str) -> bool {
    let to_single = format!("to='{}'", component_domain);
    let to_double = format!("to=\"{}\"", component_domain);

    if stanza.starts_with("<message") {
        // Benchmark messages are explicitly addressed to the component and
        // carry bb-* bodies. Ignore unrelated XML to avoid protocol noise.
        return (stanza.contains(&to_single) || stanza.contains(&to_double))
            && stanza.contains("<body>bb-");
    }

    if stanza.starts_with("<iq") {
        // IQ benchmark traffic uses explicit bb-iq-* ids.
        return stanza.contains("bb-iq-");
    }

    false
}

#[tokio::main]
async fn main() -> std::result::Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::from_default_env()
                .add_directive("rnatch_echo_bot=info".parse()?)
                .add_directive("rnatch=info".parse()?),
        )
        .init();

    let args = Args::parse();

    let enable_xmpp = args.xmpp_comp || args.all;
    let enable_rabbitmq = args.rabbitmq || args.all;
    let enable_kafka = args.kafka || args.all;
    let enable_sqs = args.sqs || args.all;

    info!("Starting rnatch echo bot");
    info!("  XMPP component: {}", enable_xmpp);
    info!("  RabbitMQ: {}", enable_rabbitmq);
    info!("  Kafka: {}", enable_kafka);
    info!("  SQS: {}", enable_sqs);

    // Create XMPP component claw
    let xmpp_comp = if enable_xmpp {
        let config = rnatch::claws::xmpp_comp::XmppCompConfig::new(
            &args.xmpp_host,
            args.xmpp_port,
            &args.xmpp_domain,
            &args.xmpp_password,
        );
        Some(Arc::new(rnatch::claws::xmpp_comp::ClawsXmppComp::new(config)))
    } else {
        None
    };

    let handler = EchoHandler {
        xmpp_comp: xmpp_comp.clone(),
        xmpp_buffer: Mutex::new(String::new()),
        xmpp_domain: args.xmpp_domain.clone(),
    };

    // XMPP burst tests can enqueue many stanzas quickly; use a larger mailbox
    // to avoid backpressure-induced read stalls on the component socket.
    let handle = Snatch::start_with_capacity(handler, 8192)?;

    // Connect XMPP component
    if let Some(ref comp) = xmpp_comp {
        comp.connect(handle.clone()).await?;
        handle.register_claw(comp.clone()).await;
    }

    // RabbitMQ bridge: consume from bb_request_q, produce to bb_response exchange
    if enable_rabbitmq {
        let amqp_uri = format!(
            "amqp://guest:guest@{}:{}/%2F",
            args.rabbitmq_host, args.rabbitmq_port
        );
        tokio::spawn(async move {
            if let Err(e) = rabbitmq_bridge(&amqp_uri).await {
                error!("RabbitMQ bridge error: {}", e);
            }
        });
    }

    // Kafka bridge: consume from bb-request, produce to bb-response
    if enable_kafka {
        let bootstrap = args.kafka_bootstrap.clone();
        tokio::spawn(async move {
            kafka_bridge(&bootstrap).await;
        });
    }

    // SQS bridge: poll bb-request, send to bb-response
    if enable_sqs {
        let endpoint = args.sqs_endpoint.clone();
        tokio::spawn(async move {
            if let Err(e) = sqs_bridge(&endpoint).await {
                error!("SQS bridge error: {}", e);
            }
        });
    }

    info!("Echo bot running. Press Ctrl+C to stop.");
    signal::ctrl_c().await?;

    info!("Shutting down...");
    if let Some(ref comp) = xmpp_comp {
        comp.disconnect().await;
    }
    handle.stop().await?;

    Ok(())
}

async fn rabbitmq_bridge(uri: &str) -> std::result::Result<(), Box<dyn std::error::Error>> {
    use lapin::{options::*, types::FieldTable, BasicProperties, Connection, ConnectionProperties};
    use futures::StreamExt;

    let conn = Connection::connect(uri, ConnectionProperties::default()).await?;
    let channel = conn.create_channel().await?;

    // Declare exchanges and queues
    channel.exchange_declare("bb_direct", lapin::ExchangeKind::Direct,
        ExchangeDeclareOptions::default(), FieldTable::default()).await?;
    channel.exchange_declare("bb_response", lapin::ExchangeKind::Direct,
        ExchangeDeclareOptions::default(), FieldTable::default()).await?;

    channel.queue_declare("bb_request_q", QueueDeclareOptions::default(),
        FieldTable::default()).await?;
    channel.queue_bind("bb_request_q", "bb_direct", "bench",
        QueueBindOptions::default(), FieldTable::default()).await?;

    let mut consumer = channel.basic_consume(
        "bb_request_q", "echo-bot",
        BasicConsumeOptions::default(), FieldTable::default(),
    ).await?;

    info!("RabbitMQ bridge started");

    while let Some(delivery) = consumer.next().await {
        if let Ok(delivery) = delivery {
            let body = delivery.data.clone();
            // Echo to response exchange
            channel.basic_publish(
                "bb_response", "bench",
                BasicPublishOptions::default(),
                &body,
                BasicProperties::default(),
            ).await?.await?;
            delivery.ack(BasicAckOptions::default()).await?;
        }
    }

    Ok(())
}

async fn kafka_bridge(bootstrap: &str) {
    use rdkafka::admin::{AdminClient, AdminOptions, NewTopic, TopicReplication};
    use rdkafka::client::DefaultClientContext;
    use rdkafka::config::ClientConfig;
    use rdkafka::consumer::{Consumer, StreamConsumer};
    use rdkafka::producer::{FutureProducer, FutureRecord};
    use rdkafka::Message;
    use futures::StreamExt;
    use std::time::Duration;

    let group_id = format!(
        "echo-bot-{}",
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_millis())
            .unwrap_or(0)
    );

    let consumer: StreamConsumer = ClientConfig::new()
        .set("bootstrap.servers", bootstrap)
        .set("group.id", &group_id)
        // Use earliest so the bridge can recover if topic creation/rebalance
        // happens shortly after producers begin publishing.
        .set("auto.offset.reset", "earliest")
        .set("enable.auto.commit", "true")
        .set("allow.auto.create.topics", "true")
        .create()
        .expect("kafka consumer");

    let producer: FutureProducer = ClientConfig::new()
        .set("bootstrap.servers", bootstrap)
        .set("message.timeout.ms", "5000")
        .set("allow.auto.create.topics", "true")
        .create()
        .expect("kafka producer");

    // Ensure request/response topics exist before subscribing/consuming.
    let admin: AdminClient<DefaultClientContext> = ClientConfig::new()
        .set("bootstrap.servers", bootstrap)
        .create()
        .expect("kafka admin client");
    let topics = [
        NewTopic::new("bb-request", 1, TopicReplication::Fixed(1)),
        NewTopic::new("bb-response", 1, TopicReplication::Fixed(1)),
    ];
    if let Ok(results) = admin.create_topics(&topics, &AdminOptions::new()).await {
        for result in results {
            if let Err(e) = result {
                // "Topic already exists" is expected on repeated runs.
                info!("Kafka topic create response: {:?}", e);
            }
        }
    }

    consumer.subscribe(&["bb-request"]).expect("subscribe");

    info!("Kafka bridge started");

    let mut stream = consumer.stream();
    while let Some(msg) = stream.next().await {
        match msg {
            Ok(msg) => {
                if let Some(payload) = msg.payload() {
                    let key = msg.key().map(|k| k.to_vec());
                    let mut record = FutureRecord::to("bb-response").payload(payload);
                    if let Some(ref k) = key {
                        record = record.key(k);
                    }
                    match producer.send(record, Duration::from_secs(5)).await {
                        Ok(_) => {}
                        Err((e, _)) => error!("Kafka produce error: {}", e),
                    }
                }
            }
            Err(e) => {
                error!("Kafka consumer error: {}", e);
            }
        }
    }
}

async fn sqs_bridge(endpoint: &str) -> std::result::Result<(), Box<dyn std::error::Error>> {
    use aws_sdk_sqs::Client as SqsClient;

    let config = aws_config::from_env()
        .region(aws_config::Region::new("us-east-1"))
        .endpoint_url(endpoint)
        .load()
        .await;
    let client = SqsClient::new(&config);

    // Ensure queues exist
    let req_url = client.create_queue().queue_name("bb-request").send().await?
        .queue_url.unwrap_or_default();
    let resp_url = client.create_queue().queue_name("bb-response").send().await?
        .queue_url.unwrap_or_default();

    info!("SQS bridge started: {} -> {}", req_url, resp_url);

    loop {
        let output = client.receive_message()
            .queue_url(&req_url)
            .max_number_of_messages(10)
            .wait_time_seconds(10)
            .send()
            .await;

        match output {
            Ok(resp) => {
                if let Some(messages) = resp.messages {
                    for msg in messages {
                        if let Some(body) = &msg.body {
                            let _ = client.send_message()
                                .queue_url(&resp_url)
                                .message_body(body)
                                .send()
                                .await;
                        }
                        if let Some(receipt) = &msg.receipt_handle {
                            let _ = client.delete_message()
                                .queue_url(&req_url)
                                .receipt_handle(receipt)
                                .send()
                                .await;
                        }
                    }
                }
            }
            Err(e) => {
                error!("SQS poll error: {}", e);
                tokio::time::sleep(std::time::Duration::from_secs(1)).await;
            }
        }
    }
}
