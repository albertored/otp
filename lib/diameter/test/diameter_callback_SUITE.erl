-module(diameter_callback_SUITE).

-export([
         suite/0,
         all/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_testcase/2,
         end_per_testcase/2
        ]).

-export([check_ack_callback/1]).
-export([handle_request/4, message_cb_old/3, message_cb_new/3]).

-include_lib("common_test/include/ct.hrl").
-include("diameter_util.hrl").
-include("diameter.hrl").
-include("diameter_gen_base_rfc3588.hrl").

suite() ->
    [{timetrap, {seconds, 60}}].

all() ->
    [check_ack_callback].

init_per_suite(Config) ->
    diameter_util:init_per_suite(Config).

end_per_suite(Config) ->
    diameter_util:end_per_suite(Config).

init_per_testcase(_Case, Config) ->
    ok = diameter:start(),
    Config.

end_per_testcase(_Case, _Config) ->
    ok = diameter:stop().

check_ack_callback(_Config) ->
    SvcS = diameter_callback_SUITE_server,
    SvcC = diameter_callback_SUITE_client,

    ServiceOpts = fun(Name) ->
                          [{'Origin-Host', atom_to_list(Name) ++ ".erlang.org"},
                           {'Origin-Realm', "erlang.org"},
                           {'Host-IP-Address', [{127,0,0,1}]},
                           {'Vendor-Id', 12345},
                           {'Product-Name', "OTP/diameter"},
                           {application, [{alias, cb_test_app},
                                          {dictionary, diameter_gen_base_rfc3588},
                                          {module, ?MODULE}]}]
                  end,

    {ok, _} = diameter:start_service(SvcS, ServiceOpts(SvcS)),
    {ok, _} = diameter:start_service(SvcC, ServiceOpts(SvcC)),

    LRef = diameter_util:listen(SvcS, tcp),

    Cb = {?MODULE, message_cb_old, [self()]},
    TransOpt = [{message_cb, Cb}],
    diameter_util:connect(SvcC, [tcp | TransOpt], LRef),

    Req = ['STR', {'Termination-Cause', ?'DIAMETER_BASE_TERMINATION-CAUSE_LOGOUT'}],
    ok = diameter:call(SvcC, cb_test_app, Req, [{extra, self()}, detach]),

    receive
        {ack_received, ok} ->
            ok;
        {ack_received, error} ->
            ct:fail(ack_in_old_callback)
    after 5000 ->
        ct:fail(timeout)
    end.

%% Server callback
handle_request(#diameter_packet{msg = ['STR'|_]}, _, _, _) ->
    {reply, ['STA', {'Result-Code', ?'DIAMETER_BASE_RESULT-CODE_SUCCESS'}]}.

%% Client callbacks
message_cb_old(send, Pkt, [Parent]) ->
    [Pkt, {callback, {?MODULE, message_cb_new, [Parent]}}];
message_cb_old(ack, _Pkt, [Parent]) ->
    Parent ! {ack_received, error},
    [];
message_cb_old(_Dir, Pkt, _State) ->
    [Pkt].

message_cb_new(ack, _Pkt, [Parent]) ->
    Parent ! {ack_received, ok},
    [];
message_cb_new(_Dir, Pkt, _State) ->
    [Pkt].
