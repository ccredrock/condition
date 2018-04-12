%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright 2018 redrock
%%% @doc condition
%%%      only_hit(<<"`a` > 5 | `b` > 6">>)
%%%      only_eval(#{`d` => `a` + `b`}>>)
%%%      only_eval(<<"`a` > 5 | `b` > 6" & #{`d` => `a` + `b`}>>)
%%% @end
%%%-------------------------------------------------------------------
-module(condition).

-export([start/0]).

-export([sync_conds/2,
         add_cond/2,
         only_hit/3,
         update_hit/3,
         only_eval/3,
         update_eval/3]).

-export([valid_cond/1,
         check_cond/1,
         mod_conds/1]).

%% callbacks
-export([start_link/0]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%%------------------------------------------------------------------------------
%% define
%%------------------------------------------------------------------------------
-record(state, {conds = #{}}).

-define(MAX_HASH_NUM, 100).
-define(HASH_ID(C), erlang:phash2(C, ?MAX_HASH_NUM)).
-define(ID_MOD(M, I), (list_to_atom("0cond_" ++ atom_to_list(M) ++ integer_to_list(I)))).
-define(HASH_MOD(M, C), ?ID_MOD(M, ?HASH_ID(C))).

%%------------------------------------------------------------------------------
%% interface
%%------------------------------------------------------------------------------
-spec start() -> {ok, [atom()]} | {error, any()}.
start() ->
    application:ensure_all_started(?MODULE).

%%------------------------------------------------------------------------------
-spec sync_conds(Mod::atom(), CondList::[binary()]) -> ok | {error, any()}.
sync_conds(Mod, CondList) ->
    case catch gen_server:call(?MODULE, {sync_conds, Mod, CondList}) of
        ok -> ok;
        {_, Reason} -> {error, Reason}
    end.

-spec add_cond(Mod::atom(), Cond::binary()) -> ok | {error, any()}.
add_cond(Mod, Cond) ->
    case catch gen_server:call(?MODULE, {add_cond, Mod, Cond}) of
        ok -> ok;
        {_, Reason} -> {error, Reason}
    end.

-spec only_hit(Mod::atom(), Cond::binary(), Data::#{}) -> boolean().
only_hit(Mod, Cond, Data) ->
    (catch ?HASH_MOD(Mod, Cond):hit(Cond, Data)) =:= true.

-spec update_hit(Mod::atom(), Cond::binary(), Data::#{}) -> boolean().
update_hit(Mod, Cond, Data) ->
    Mod1 = ?HASH_MOD(Mod, Cond),
    case {code:is_loaded(Mod), catch Mod1:hit(Cond, Data)} of
        {true, true} -> true;
        {false, _} ->
            case add_cond(Mod, Cond) of
                ok -> only_hit(Mod, Cond, Data);
                {error, _} -> false
            end;
        _ -> false
    end.

-spec only_eval(Mod::atom(), Cond::binary(), Data::#{}) -> undefined | #{}.
only_eval(Mod, Cond, Data) ->
    case catch ?HASH_MOD(Mod, Cond):hit(Cond, Data) of
        #{} = V -> V;
        _ -> undefined
    end.

-spec update_eval(Mod::atom(), Cond::binary(), Data::#{}) -> undefined | #{}.
update_eval(Mod, Cond, Data) ->
    Mod1 = ?HASH_MOD(Mod, Cond),
    case {code:is_loaded(Mod), catch Mod1:hit(Cond, Data)} of
        {true,  #{} = V} -> V;
        {false, _} ->
            case add_cond(Mod, Cond) of
                ok -> only_eval(Mod, Cond, Data);
                {error, _} -> undefined
            end;
        _ -> undefined
    end.

%%------------------------------------------------------------------------------
-spec valid_cond(Cond::binary()) -> boolean().
valid_cond(Cond) ->
    case catch check_cond(Cond) of
        {ok, _} -> true;
        _ -> false
    end.

-spec check_cond(Cond::binary()) -> {ok, binary()} | {error, any()}.
check_cond(<<_/binary>> = Cond) ->
    Cond1 = convert_key(convert_op(Cond), check),
    try
        {ok, Parsed} = parse_exprs(<<"M = #{}, ", Cond1/binary>>),
        {value, _, _} = erl_eval:exprs(Parsed, []),
        {ok, Cond1}
    catch
        _:R -> {error, {Cond1, R}}
    end.

%% @private
parse_exprs(Cond) ->
    {ok, Scanned, _} = erl_scan:string(binary_to_list(<<Cond/binary, ".">>)),
    erl_parse:parse_exprs(Scanned).

%% @private
%% args: "`a` = \"5a\" & `b` ~="
%% return: "`a` =:= \"5a\" andalso `b` =="
convert_op(Cond) ->
    List = [{<<":">>, <<>>},
            {<<"&">>, <<" andalso ">>},
            {<<"\\|">>, <<" orelse ">>},
            {<<"([^!~<>])=(^>)">>, <<"\\1=:=\\2">>},
            {<<"!=">>, <<"/=">>},
            {<<"~=">>, <<"==">>},
            {<<"<=">>, <<"=<">>}],
    lists:foldl(fun({Src, Dst}, Acc) -> re:replace(Acc, Src, Dst, [{return, binary}, global]) end, Cond, List).

convert_key(Cond, check) ->
    List = [{<<"`([a-z,A-Z]\+)` * =>">>, <<"<<\"\\1\">> =>">>},
            {<<"`([a-z,A-Z]\+)`">>, <<"maps:get(<<\"\\1\">>, M, 0)">>}],
    lists:foldl(fun({Src, Dst}, Acc) -> re:replace(Acc, Src, Dst, [{return, binary}, global]) end, Cond, List);
convert_key(Cond, run) ->
    List = [{<<"`([a-z,A-Z]\+)` * =>">>, <<"<<\"\\1\">> =>">>},
            {<<"`([a-z,A-Z]\+)`">>, <<"maps:get(<<\"\\1\">>, M)">>}],
    lists:foldl(fun({Src, Dst}, Acc) -> re:replace(Acc, Src, Dst, [{return, binary}, global]) end, Cond, List).

mod_conds(Mod) ->
    State = sys:get_state(?MODULE),
    maps:from_list([{?ID_MOD(Mod, I), M} || {I, M} <- maps:to_list(maps:get(Mod, State#state.conds, #{}))]).

%%------------------------------------------------------------------------------
%% gen_server
%%------------------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | {error, any()}.
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

%% @hidden
init([]) ->
    process_flag(trap_exit, true),
    error_logger:info_msg("start condition"),
    {ok, #state{}, 0}.

%% @hidden
handle_call({sync_conds, Mod, CondList}, _From, State) ->
    {Result, State1} = handle_sync_conds(Mod, CondList, State),
    {reply, Result, State1};
handle_call({add_cond, Mod, Cond}, _From, State) ->
    {Result, State1} = handle_add_cond(Mod, Cond, State),
    {reply, Result, State1};
handle_call(_Call, _From, State) ->
    {reply, ok, State}.

%% @hidden
handle_cast(_Request, State) ->
    {noreply, State}.

%% @hidden
handle_info(_Info, State) ->
    {noreply, State}.

%% @hidden
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% @hidden
terminate(_Reason, _State) -> ok.

%%------------------------------------------------------------------------------
%% @private
handle_sync_conds(Mod, CondList, State) ->
    Map = (catch form_hash_map(lists:usort(CondList), #{})),
    case catch replace_mod([{?ID_MOD(Mod, I), L} || {I, L} <- maps:to_list(Map)]) of
        ok ->
            error_logger:info_msg("start condition ~p", [Map]),
            {ok, State#state{conds = #{Mod => Map}}};
        {error, Reason} -> {{error, Reason}, State}
    end.

form_hash_map([H | T], Map) ->
    L = maps:get(HashID = ?HASH_ID(H), Map, []),
    form_hash_map(T, Map#{HashID => [H | L]});
form_hash_map([], Map) -> Map.

%% @private
handle_add_cond(Mod, Cond, #state{conds = ModMap} = State) ->
    HashID = ?HASH_ID(Cond),
    HashMap = maps:get(Mod, ModMap, #{}),
    CondList = lists:usort([Cond | maps:get(HashID, HashMap, [])]),
    case catch replace_mod([{?ID_MOD(Mod, HashID), CondList}]) of
        ok -> {ok, State#state{conds = ModMap#{Mod => HashMap#{HashID => CondList}}}};
        {error, Reason} -> {{error, Reason}, State}
    end.

%%------------------------------------------------------------------------------
%% expr
%%------------------------------------------------------------------------------
%% @private
replace_mod([{Mod, List} | T]) ->
    try
        Forms = [erl_syntax:revert(X) || X <- form_abstract(Mod, List)],
        {ok, _, Bin} = compile:forms(Forms, [verbose, report_errors]),
        case code:soft_purge(Mod) of
            false ->
                {error, {purge_fail, Mod}};
            true ->
                {module, Mod} = code:load_binary(Mod, atom_to_list(Mod) ++ ".erl", Bin),
                replace_mod(T)
        end
    catch
        _:R ->
            {error, {R, erlang:get_stacktrace()}}
    end;
replace_mod([]) -> ok.

%% @private
form_abstract(Mod, List) ->
    [%% -module(Mod).
     erl_syntax:attribute(
       erl_syntax:atom(module),
       [erl_syntax:atom(Mod)]),
     %% -export([hit/2]).
     erl_syntax:attribute(
       erl_syntax:atom(export),
       [erl_syntax:list(
          [erl_syntax:arity_qualifier(
             erl_syntax:atom(hit),
             erl_syntax:integer(2))])]),
     %% hit(CondBin, M) -> Bool;
     %% hit(_, _) -> Bool.
     erl_syntax:function(
       erl_syntax:atom(hit),
       [erl_syntax:clause([form_binary(Val),
                           erl_syntax:variable('M')],
                          none, form_exprs(Val))
        || Val <- List]
       ++ [erl_syntax:clause([erl_syntax:underscore(),
                              erl_syntax:underscore()],
                             none, [erl_syntax:atom(undefined)])])].

%% @private
form_binary(Bin) ->
    {bin,0,
     [{bin_element,0,
       {string,0,binary_to_list(Bin)},
       default,default}]}.

%% @private
form_exprs(Cond) ->
    Cond1 = convert_key(convert_op(Cond), check),
    {ok, Parsed} = parse_exprs(Cond1),
    Parsed.

