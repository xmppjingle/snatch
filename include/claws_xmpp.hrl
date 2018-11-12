-record(iq, {
  from,
  to,
  id,
  type,
  raw,
  payload,
  ns
  }).

-record(presence, {
  from,
  to,
  id,
  type,
  raw,
  payload,
  ns
  }).

-record(message, {
  from,
  to,
  id,
  type,
  raw,
  payload,
  ns
  }).

-define(IQ, <<"iq">>).
-define(PRESENCE, <<"presence">>).
-define(MESSAGE, <<"message">>).