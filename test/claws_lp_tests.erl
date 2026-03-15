-module(claws_lp_tests).
-compile([warnings_as_errors, debug_info]).

-include_lib("eunit/include/eunit.hrl").

%% read_chunk/3 tests — this is a pure function we can test directly

read_chunk_initial_parse_test() ->
    %% Simulates first chunk with hex size header followed by CRLF and data
    %% "a\r\n" means 10 bytes of content
    Size = <<"a\r\n">>,
    Data = <<"0123456789">>,
    Chunk = <<Size/binary, Data/binary>>,
    Result = claws_lp:read_chunk(-1, <<>>, Chunk),
    ?assertEqual({chunk, 10, <<"0123456789">>, <<>>}, Result).

read_chunk_wait_for_more_data_test() ->
    %% Size says 10, but we only have 5 bytes
    Size = <<"a\r\n">>,
    Data = <<"01234">>,
    Chunk = <<Size/binary, Data/binary>>,
    {wait, NSize, _NBuffer} = claws_lp:read_chunk(-1, <<>>, Chunk),
    ?assertEqual(10, NSize).

read_chunk_complete_with_known_size_test() ->
    %% Already know the size, and have enough data
    Result = claws_lp:read_chunk(5, <<"hel">>, <<"lo">>),
    ?assertEqual({chunk, 5, <<"hello">>, <<>>}, Result).

read_chunk_wait_with_known_size_test() ->
    %% Already know the size, but still not enough data
    Result = claws_lp:read_chunk(10, <<"hel">>, <<"lo">>),
    ?assertEqual({wait, 10, <<"hello">>}, Result).

read_chunk_with_remainder_test() ->
    %% More data than needed — remainder should be returned
    Result = claws_lp:read_chunk(3, <<>>, <<"abcdef">>),
    ?assertEqual({chunk, 3, <<"abc">>, <<"def">>}, Result).

read_chunk_buffer_accumulation_test() ->
    %% Buffer from previous call plus new data
    Result = claws_lp:read_chunk(6, <<"abc">>, <<"def">>),
    ?assertEqual({chunk, 6, <<"abcdef">>, <<>>}, Result).

read_chunk_hex_size_parsing_test() ->
    %% "ff\r\n" = 255 bytes, but only 3 bytes of data — should wait
    Chunk = <<"ff\r\nabc">>,
    {wait, NSize, _} = claws_lp:read_chunk(-1, <<>>, Chunk),
    ?assertEqual(255, NSize).
