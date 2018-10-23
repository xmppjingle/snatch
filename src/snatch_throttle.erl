-module(snatch_throttle).

-include("snatch.hrl").

% List of Binary ID 
-callback get_whitelist(Cfg :: map()) -> Whitelist :: [ IDs :: binary()].

-callback get_params(Packet :: any(), #via{}) -> {Id :: binary(), Max :: pos_integer(), Period :: pos_integer()}.

-callback dropped(Packet :: any(), #via{}) -> any().