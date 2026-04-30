-module(socks5_client).
-export([connect/4]).

%% Connect to a destination through a SOCKS5 proxy (no authentication)
%% Returns {ok, Socket} on success
connect(ProxyHost, ProxyPort, DestHost, DestPort) ->
    %% Step 1: Connect to SOCKS5 proxy
    error_logger:error_msg("Connecting to SOCKS5 proxy ~s:~p~n", [ProxyHost, ProxyPort]),
    case gen_tcp:connect(ProxyHost, ProxyPort, [binary, {active, false} ]) of
        {ok, Socket} ->
            try
                %% Step 2: Send greeting (no authentication method)
    error_logger:error_msg("1", []),
                ok = gen_tcp:send(Socket, <<5, 1, 0>>),
                
                %% Step 3: Receive method selection
    error_logger:error_msg("2", []),
                {ok, <<5, 0>>} = gen_tcp:recv(Socket, 2),
                
                %% Step 4: Send connection request
    error_logger:error_msg("3", []),
                ok = send_connect_request(Socket, DestHost, DestPort),
                
                %% Step 5: Receive connection response
    error_logger:error_msg("4", []),
                case receive_connect_response(Socket) of
                    ok -> 
    error_logger:error_msg("5", []),
                        
                        {ok, Socket};
                    {error, Reason} -> 
                        gen_tcp:close(Socket),
                        {error, Reason}
                end
            catch
                _:Error ->
                    gen_tcp:close(Socket),
                    {error, Error}
            end;
        {error, Reason} ->
            {error, Reason}
    end.

%% Send CONNECT request
send_connect_request(Socket, DestHost, DestPort) when is_list(DestHost) ->
    send_connect_request(Socket, list_to_binary(DestHost), DestPort);
send_connect_request(Socket, DestHost, DestPort) when is_binary(DestHost) ->
    HostLen = byte_size(DestHost),
    %% [Version, Command(CONNECT=1), Reserved, AddrType(DOMAINNAME=3), ...]
    Packet = <<5, 1, 0, 3, HostLen, DestHost/binary, DestPort:16>>,
    gen_tcp:send(Socket, Packet).

%% Receive CONNECT response
receive_connect_response(Socket) ->
    case gen_tcp:recv(Socket, 4) of
        {ok, <<5, 0, 0, AddrType>>} ->
            %% Success - consume the rest of the response
            consume_address(Socket, AddrType),
            ok;
        {ok, <<5, ErrorCode, 0, _>>} ->
            {error, socks5_error(ErrorCode)};
        {error, Reason} ->
            {error, Reason}
    end.

%% Consume the bound address from response
consume_address(Socket, 1) ->
    %% IPv4: 4 bytes + 2 bytes port
    gen_tcp:recv(Socket, 6);
consume_address(Socket, 3) ->
    %% Domain: 1 byte length + domain + 2 bytes port
    {ok, <<Len>>} = gen_tcp:recv(Socket, 1),
    gen_tcp:recv(Socket, Len + 2);
consume_address(Socket, 4) ->
    %% IPv6: 16 bytes + 2 bytes port
    gen_tcp:recv(Socket, 18).

%% Translate SOCKS5 error codes
socks5_error(1) -> general_failure;
socks5_error(2) -> connection_not_allowed;
socks5_error(3) -> network_unreachable;
socks5_error(4) -> host_unreachable;
socks5_error(5) -> connection_refused;
socks5_error(6) -> ttl_expired;
socks5_error(7) -> command_not_supported;
socks5_error(8) -> address_type_not_supported;
socks5_error(_) -> unknown_error.

%% Example usage for SMTP:
%% 
%% {ok, Socket} = socks5_client:connect("proxy.example.com", 1080, 
%%                                       "smtp.gmail.com", 587).
%%
%% %% Use the socket for SMTP:
%% {ok, Greeting} = gen_tcp:recv(Socket, 0, 5000),
%% io:format("SMTP: ~s", [Greeting]),
%% 
%% gen_tcp:send(Socket, "EHLO client.example.com\r\n"),
%% {ok, Response} = gen_tcp:recv(Socket, 0, 5000),
%% 
%% gen_tcp:close(Socket).