-module(claws_dummy).
-compile([warnings_as_errors, debug_info, export_all]).

send(Data, JID) ->
    snatch_tests ! {?MODULE, Data, JID, undefined},
    ok.

send(Data, JID, ID) ->
    snatch_tests ! {?MODULE, Data, JID, ID},
    ok.
