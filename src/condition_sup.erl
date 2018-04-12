%%%-------------------------------------------------------------------
%%% @author ccredrock@gmail.com
%%% @copyright 2018 redrock
%%% @doc condition
%%% @end
%%%-------------------------------------------------------------------
-module(condition_sup).

-export([start_link/0, init/1]).

%%------------------------------------------------------------------------------
-behaviour(supervisor).

%%------------------------------------------------------------------------------
-spec start_link() -> supervisor:startlink_ret().
start_link() ->
    {ok, Sup} = supervisor:start_link({local, ?MODULE}, ?MODULE, []),
    {ok, _} = supervisor:start_child(?MODULE, {condition,
                                               {condition, start_link, []},
                                               transient, infinity, worker,
                                               [condition]}),
    {ok, Sup}.

-spec init([]) -> supervisor:init().
init([]) ->
    {ok, {{one_for_one, 1, 60}, []}}.

