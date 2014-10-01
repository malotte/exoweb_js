%%% -*- coding: latin-1 -*-
%%%---- BEGIN COPYRIGHT -------------------------------------------------------
%%%
%%% Copyright (C) 2013-2014 Feuerlabs, Inc. All rights reserved.
%%%
%%% This Source Code Form is subject to the terms of the Mozilla Public
%%% License, v. 2.0. If a copy of the MPL was not distributed with this
%%% file, You can obtain one at http://mozilla.org/MPL/2.0/.
%%%
%%%---- END COPYRIGHT ---------------------------------------------------------
%%% @author Malotte W L�nne <malotte@malotte.net>
%%% @doc
%%%    Exoweb cookie server for web session
%%% Created : Sepetember 2014 by Malotte W L�nne
%%% @end
-module(exoweb_cookie_handler).
-behaviour(gen_server).

-include_lib("lager/include/log.hrl").
-include("exoweb.hrl").

%% general api
-export([start_link/1, 
	 stop/0]).

%% functional api
-export([store/1,
	 retreive/1,
	 read/1]).

%% gen_server callbacks
-export([init/1, 
	 handle_call/3, 
	 handle_cast/2, 
	 handle_info/2,
	 terminate/2, 
	 code_change/3]).

%% test api
-export([dump/0]).

-import(exoweb_lib, [get_env/2, sec/0]).

-define(SERVER, ?MODULE). 

%% Loop data
-record(ctx,
	{
	  state = running,
	  cookies,
	  queue
	}).

%%%===================================================================
%%% API
%%%===================================================================
%%--------------------------------------------------------------------
%% @doc
%% Starts the server.
%% Loads configuration from File.
%% @end
%%--------------------------------------------------------------------
-spec start_link([]) -> 
			{ok, Pid::pid()} | 
			ignore | 
			{error, Error::term()}.

start_link(Opts) ->
    lager:info("~p: start_link: args = ~p\n", [?MODULE, Opts]),
    gen_server:start_link({local, ?SERVER}, ?MODULE, Opts, []).


%%--------------------------------------------------------------------
%% @doc
%% Stops the server.
%% @end
%%--------------------------------------------------------------------
-spec stop() -> ok | {error, Error::term()}.

stop() ->
    gen_server:call(?SERVER, stop).


%%--------------------------------------------------------------------
%% @doc
%% Store cookie data
%%
%% @end
%%--------------------------------------------------------------------
-spec store(Cookie::#exoweb_cookie{}) -> 
		   WebCookie::integer() | {error, Error::atom()}.

store(Cookie) when is_record(Cookie, exoweb_cookie) ->
    %% Or execute here, change ets to public ??
    gen_server:call(?SERVER, {store, Cookie}).

%%--------------------------------------------------------------------
%% @doc
%% Retrieve cookie data
%%
%% @end
%%--------------------------------------------------------------------
-spec retreive(Id::integer() | string()) -> 
		      {ok, Cookie::#exoweb_cookie{}} | 
		      {error, Error::atom()}.

retreive(Id) when is_list(Id) ->
    call(Id, fun retreive/1);
retreive(Id) when is_integer(Id) ->
    %% Or execute here, change ets to public??
    gen_server:call(?SERVER, {retreive, Id}).

%%--------------------------------------------------------------------
%% @doc
%% Read cookie data
%%
%% @end
%%--------------------------------------------------------------------
-spec read(Id::integer() | string()) -> 
		      {ok, Cookie::#exoweb_cookie{}} | 
		      {error, Error::atom()}.

read(Id) when is_list(Id) ->
    call(Id, fun read/1);
read(Id) when is_integer(Id) ->
    %% Or execute here, change ets to public ??
    gen_server:call(?SERVER, {read, Id}).

%%--------------------------------------------------------------------
%% @doc
%% Dumps data to standard output.
%%
%% @end
%%--------------------------------------------------------------------
-spec dump() -> ok | {error, Error::atom()}.

dump() ->
    gen_server:call(?SERVER, dump).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(Args::list()) -> 
		  {ok, Ctx::#ctx{}} |
		  {stop, Reason::term()}.

init(_Args) ->
    lager:info("~p: init: args = ~p,\n pid = ~p\n", [?MODULE, _Args, self()]),
    CookieTable = ets:new(exoweb_cookie_table, 
			   [private, ordered_set, named_table,
			    {keypos, #exoweb_cookie.id}]),
    TimeQueue = ets:new(exoweb_cookie_queue, 
			[private, ordered_set, named_table]),
    {ok, #ctx {cookies = CookieTable, queue = TimeQueue}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages.
%% Request can be the following:
%% <ul>
%% <li> dump - Writes loop data to standard out (for debugging).</li>
%% <li> stop - Stops the application.</li>
%% </ul>
%%
%% @end
%%--------------------------------------------------------------------
-type call_request()::
	{store, Cookie::#exoweb_cookie{}} |
	{retreive, Id::integer()} |
	{read, Id::integer()} |
	dump |
	stop.

-spec handle_call(Request::call_request(), From::{pid(), Tag::term()}, Ctx::#ctx{}) ->
			 {reply, Reply::term(), Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::atom(), Reply::term(), Ctx::#ctx{}}.

handle_call({store, Cookie=#exoweb_cookie{}}, _From, 
	    Ctx=#ctx {cookies = Cookies, queue = Queue}) ->
    ?dbg("handle_call: store ~p", [Cookie]),
    <<Id:64>> = crypto:rand_bytes(8),
    
    %% Cookie expiration time set in environment, default 24 hours
    ets:insert(Queue, {sec() + get_env(cookie_expiration_time,24*60*60), Id}),
    ets:insert(Cookies, Cookie#exoweb_cookie {id = Id}), 

    clean_tables(Ctx),

    {reply, Id, Ctx};

handle_call({retreive, Id}, _From, 
	    Ctx=#ctx {cookies = Cookies, queue = Queue}) ->
    ?dbg("handle_call: retreive ~p", [Id]),
    
    Reply = 
	case ets:lookup(Cookies, Id) of
	    [Cookie] ->
		ets:delete(Cookies, Id), 
		ets:match_delete(Queue, {'_', Id}),
		{ok, Cookie};
	    [] ->
		{error, not_found}
	end,
    clean_tables(Ctx),

    {reply, Reply, Ctx};

handle_call({read, Id}, _From, Ctx=#ctx {cookies = Cookies}) ->
    ?dbg("handle_call: read ~p", [Id]),
    
    Reply = 
	case ets:lookup(Cookies, Id) of
	    [Cookie] ->
		{ok, Cookie};
	    [] ->
		{error, not_found}
	end,
    clean_tables(Ctx),

    {reply, Reply, Ctx};

handle_call(dump, _From, Ctx=#ctx {cookies = Cookies, queue = Queue}) ->
    io:format("Ctx: ~p~n", [Ctx]),
    io:format("Queue:~n",[]),
    ets:foldl(fun(Q, _A) -> io:format("~p~n",[Q]) end, [], Queue),
    io:format("Cookie table:~n",[]),
    ets:foldl(fun(S, _A) -> io:format("~p~n",[S]) end, [], Cookies),
    {reply, ok, Ctx};

handle_call(stop, _From, Ctx) ->
    ?dbg("stop:",[]),
    {stop, normal, ok, Ctx};

handle_call(_Request, _From, Ctx) ->
    ?dbg("handle_call: unknown request ~p", [_Request]),
    {reply, {error,bad_call}, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages.
%%
%% @end
%%--------------------------------------------------------------------
-type cast_msg()::
	term().

-spec handle_cast(Msg::cast_msg(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_cast(_Msg, Ctx) ->
    ?dbg("handle_cast: unknown msg ~p", [_Msg]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages.
%% 
%% @end
%%--------------------------------------------------------------------
-type info()::
	term().

-spec handle_info(Info::info(), Ctx::#ctx{}) -> 
			 {noreply, Ctx::#ctx{}} |
			 {noreply, Ctx::#ctx{}, Timeout::timeout()} |
			 {stop, Reason::term(), Ctx::#ctx{}}.

handle_info(_Info, Ctx) ->
    ?dbg("handle_info: unknown info ~p", [_Info]),
    {noreply, Ctx}.

%%--------------------------------------------------------------------
%% @private
%%--------------------------------------------------------------------
-spec terminate(Reason::term(), Ctx::#ctx{}) -> 
		       no_return().

terminate(_Reason, _Ctx=#ctx {state = State}) ->
    ?dbg("terminate: terminating in state ~p, reason = ~p",
	 [State, _Reason]),
    ok.
%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process ctx when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term(), Ctx::#ctx{}, Extra::term()) -> 
			 {ok, NewCtx::#ctx{}}.

code_change(_OldVsn, Ctx, _Extra) ->
    ?dbg("code_change: old version ~p", [_OldVsn]),
    {ok, Ctx}.


%%--------------------------------------------------------------------
%%
%% Internal
%% 
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
%% @doc
%% Removes old cookies
%%
%% @end
%%--------------------------------------------------------------------
-spec clean_tables(Ctx::#ctx{}) -> ok.

clean_tables(_Ctx=#ctx {cookies = Cookies, queue = Queue}) ->
    %% Clean away old cookies
    Now = sec(),
    OldCookies = 
	ets:select(Queue, [{{'$1','$2'},[{'<', '$1', Now}], ['$2']}]),
    ?dbg("clean: old cookies ~p.", [OldCookies]),
    ets:select_delete(Queue, [{{'$1','$2'},[{'<', '$1', Now}], [true]}]),
    lists:foreach(fun(S) -> ets:delete(Cookies, S) end, OldCookies),
    ok.
    
%%--------------------------------------------------------------------
call(Id, F) ->
    try list_to_integer(Id) of
	I -> apply(F, [I])
    catch
	error: _E ->
	    ?dbg("call: ~p not integer.", [Id]),
	    {error, illegal_id}
    end.