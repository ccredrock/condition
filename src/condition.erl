%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright 2018 redrock
%%% @doc condition
%%% @end
%%%-------------------------------------------------------------------
-module(condition).

-export([start/0]).

-export([human_hit/3]).

-export([sync_conds/2]).

%% callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------
%% define
%%------------------------------------------------------------------------------
-record(state, {}).

-define(MAX_HASH_NUM, 100).

%%------------------------------------------------------------------------------
%% interface
%%------------------------------------------------------------------------------
-spec start() -> {ok, [atom()]} | {error, any()}.
start() ->
    application:ensure_all_started(?MODULE).

-spec sync_conds(Mod::atom(), CondList::[binary()]) -> ok.
sync_conds(Mod, CondList) ->
    ok = reload_mod(Mod, CondList).

-spec human_hit(Mod::atom(), Cond::binary(), Map::#{}) -> boolean().
human_hit(Mod, Cond, Map) ->
    %%Hash = erlang:phash2(Cond, ?MAX_HASH_NUM),
    %%Mod1 = atom_to_list(Mod) ++ integer_to_list(Hash),
    (catch Mod:human_hit(Cond, Map)) =:= true.

%%------------------------------------------------------------------------------
%% expr
%%------------------------------------------------------------------------------
reload_mod(Mod, List) ->
    try
        Forms = [erl_syntax:revert(X) || X <- form_abstract(Mod, List)],
        {ok, _, Bin} = compile:forms(Forms, [verbose, report_errors]),
        case code:soft_purge(Mod) of
            false ->
                {error, purge_fail};
            true ->
                {module, Mod} = code:load_binary(Mod, atom_to_list(Mod) ++ ".erl", Bin),
                ok
        end
    catch
        _:R ->
            {error, R}
    end.

form_abstract(Mod, List) ->
    [%% -module(Mod).
     erl_syntax:attribute(
       erl_syntax:atom(module),
       [erl_syntax:atom(Mod)]),
     %% -export([human_hit/2]).
     erl_syntax:attribute(
       erl_syntax:atom(export),
       [erl_syntax:list(
          [erl_syntax:arity_qualifier(
             erl_syntax:atom(human_hit),
             erl_syntax:integer(2))])]),
     %% hit(CondBin, Map) -> Bool;
     %% hit(_, _) -> Bool.
     erl_syntax:function(
       erl_syntax:atom(human_hit),
       [erl_syntax:clause([erl_syntax:abstract(Val),
                           erl_syntax:variable('Map')],
                          none, form_exprs(Val))
        || Val <- List]
       ++ [erl_syntax:clause([erl_syntax:underscore(),
                              erl_syntax:underscore()],
                             none, [erl_syntax:atom(false)])])].

form_exprs(Bin) ->
    Bin1 = form_map_get(form_erl_expr(Bin)),
    {ok, Scanned, _} = erl_scan:string(binary_to_list(<<Bin1/binary, ".">>)),
    {ok, Parsed} = erl_parse:parse_exprs(Scanned),
    Parsed.

%% "`a` == \"5a\" andalso `b` =="
form_erl_expr(Cond) ->
    List = [{<<"&">>, <<" andalso ">>},
            {<<"\\|">>, <<" orelse ">>},
            {<<"!=">>, <<"/=">>},
            {<<"~=">>, <<"==">>},
            {<<"<=">>, <<"=<">>},
            {<<"=">>, <<"=:=">>}],
    lists:foldl(fun({Src, Dst}, Acc) -> re:replace(Acc, Src, Dst, [{return, binary}, global]) end, Cond, List).

%% "maps:get(<<\"a\">>, Map) == \"5a\" andalso maps:get(<<\"b\">>, Map) =="
form_map_get(Cond) ->
    re:replace(Cond, <<"`([a-z,A-Z]\+)`">>, <<"maps:get(<<\"\\1\">>, Map, undefined)">>, [{return, binary}, global]).

%%------------------------------------------------------------------------------
%% gen_server
%%------------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    gen_server:start_link(?MODULE, [], []).

%% @hidden
init([]) ->
    process_flag(trap_exit, true),
    error_logger:info_msg("start condition"),
    {ok, #state{}, 0}.

%% @hidden
handle_call(_Call, _From, State) ->
    {reply, ok, State}.

%% @hidden
handle_cast(_Request, State) ->
    {noreply, State}.

%% @hidden
handle_info(timeout, State) ->
    {noreply, handle_timeout(State)};
handle_info(_Info, State) ->
    {noreply, State}.

%% @hidden
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @hidden
terminate(_Reason, _State) -> ok.

%%------------------------------------------------------------------------------
%% @private
handle_timeout(#state{} = State) -> State.

