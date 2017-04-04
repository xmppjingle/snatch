-module(claws).

-callback send(Data::binary(), JID::binary()) -> any().
