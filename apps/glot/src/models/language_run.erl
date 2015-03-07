-module(language_run).

-export([
    run/3
]).

run(Language, Version, Files) ->
    Image = language:get_image(Language, Version),
    Config = config:docker_container_config(Image),
    log:event(<<"Create container from image ", Image/binary>>),
    ContainerId = docker:container_create(Config),
    RemoveRef = remove_after(config:docker_run_timeout() + 5, ContainerId),
    log:event(<<"Start container ", ContainerId/binary>>),
    docker:container_start(ContainerId),
    log:event(<<"Attach container ", ContainerId/binary>>),
    Pid = docker:container_attach(ContainerId),
    DetachRef = detach_timeout_after(config:docker_run_timeout(), Pid),
    Payload = prepare_payload(Language, Files),
    log:event([<<"Send payload to ">>, ContainerId, <<" via ">>, util:pid_to_binary(Pid)]),
    Res = docker:container_send(Pid, Payload),
    cancel_timer(DetachRef),
    cancel_timer(RemoveRef),
    log:event(<<"Remove container ", ContainerId/binary>>),
    docker:container_remove(ContainerId),
    Res.

remove_after(Seconds, ContainerId) ->
    {ok, Ref} = timer:apply_after(
        Seconds * 1000,
        docker,
        container_remove,
        [ContainerId]
    ),
    Ref.

detach_timeout_after(Seconds, Pid) ->
    {ok, Ref} = timer:apply_after(
        Seconds * 1000,
        docker,
        container_detach,
        [Pid, timeout]
    ),
    Ref.

cancel_timer(Ref) ->
    timer:cancel(Ref).

prepare_payload(Language, Files) ->
    jsx:encode(#{
        <<"language">> => Language,
        <<"files">> => Files
    }).