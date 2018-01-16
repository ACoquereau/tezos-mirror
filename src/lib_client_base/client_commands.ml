(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

type ('a, 'b) lwt_format =
  ('a, Format.formatter, unit, 'b Lwt.t) format4

class type logger_sig = object
  method error : ('a, 'b) lwt_format -> 'a
  method warning : ('a, unit) lwt_format -> 'a
  method message : ('a, unit) lwt_format -> 'a
  method answer :  ('a, unit) lwt_format -> 'a
  method log : string -> ('a, unit) lwt_format -> 'a
end

class logger log =
  let message =
    (fun x ->
       Format.kasprintf (fun msg -> log "stdout" msg) x) in
  object
    method error : type a b. (a, b) lwt_format -> a =
      Format.kasprintf
        (fun msg ->
           Lwt.fail (Failure msg))
    method warning : type a. (a, unit) lwt_format -> a =
      Format.kasprintf
        (fun msg -> log "stderr" msg)
    method message : type a. (a, unit) lwt_format -> a = message
    method answer : type a. (a, unit) lwt_format -> a = message
    method log : type a. string -> (a, unit) lwt_format -> a =
      fun name ->
        Format.kasprintf
          (fun msg -> log name msg)
  end

class type wallet = object
  method load : string -> default:'a -> 'a Data_encoding.encoding -> 'a tzresult Lwt.t
  method write : string -> 'a -> 'a Data_encoding.encoding -> unit tzresult Lwt.t
end

class type block = object
  method block : Node_rpc_services.Blocks.block
end

class type logging_wallet = object
  inherit logger
  inherit wallet
end

class type logging_rpcs = object
  inherit logger
  inherit Client_rpcs.ctxt
end

class type full_context = object
  inherit logger
  inherit wallet
  inherit Client_rpcs.ctxt
  inherit block
end


class file_wallet dir : wallet = object (self)
  method private filename alias_name =
    Filename.concat
      dir
      (Str.(global_replace (regexp_string " ") "_" alias_name) ^ "s")

  method load : type a. string -> default:a -> a Data_encoding.encoding -> a tzresult Lwt.t =
    fun alias_name ~default encoding ->
      let filename = self#filename alias_name in
      if not (Sys.file_exists filename) then
        return default
      else
        Data_encoding_ezjsonm.read_file filename
        |> generic_trace
          "couldn't to read the %s file" alias_name >>=? fun json ->
        match Data_encoding.Json.destruct encoding json with
        | exception _ -> (* TODO print_error *)
            failwith "didn't understand the %s file" alias_name
        | data ->
            return data

  method write :
    type a. string -> a -> a Data_encoding.encoding -> unit tzresult Lwt.t =
    fun alias_name list encoding ->
      Lwt.catch
        (fun () ->
           Lwt_utils.create_dir dir >>= fun () ->
           let filename = self#filename alias_name in
           let json = Data_encoding.Json.construct encoding list in
           Data_encoding_ezjsonm.write_file filename json)
        (fun exn -> Lwt.return (error_exn exn))
      |> generic_trace "could not write the %s alias file." alias_name
end

type command = (full_context, unit) Cli_entries.command

(* Default config *)

let (//) = Filename.concat

let home =
  try Sys.getenv "HOME"
  with Not_found -> "/root"

let default_base_dir = home // ".tezos-client"

let default_block = `Prevalidation

let default_log ~base_dir channel msg =
  let startup =
    CalendarLib.Printer.Precise_Calendar.sprint
      "%Y-%m-%dT%H:%M:%SZ"
      (CalendarLib.Calendar.Precise.now ()) in
  match channel with
  | "stdout" ->
      print_endline msg ;
      Lwt.return ()
  | "stderr" ->
      prerr_endline msg ;
      Lwt.return ()
  | log ->
      let (//) = Filename.concat in
      Lwt_utils.create_dir (base_dir // "logs" // log) >>= fun () ->
      Lwt_io.with_file
        ~flags: Unix.[ O_APPEND ; O_CREAT ; O_WRONLY ]
        ~mode: Lwt_io.Output
        (base_dir // "logs" // log // startup)
        (fun chan -> Lwt_io.write chan msg)

let make_context
    ?(base_dir = default_base_dir)
    ?(block = default_block)
    ?(rpc_config = Client_rpcs.default_config)
    log =
  object
    inherit logger log
    inherit file_wallet base_dir
    inherit Client_rpcs.http_ctxt rpc_config
    method block = block
  end

let ignore_context =
  make_context (fun _ _ -> Lwt.return ())

exception Version_not_found

let versions = Protocol_hash.Table.create 7

let get_versions () =
  Protocol_hash.Table.fold
    (fun k c acc -> (k, c) :: acc)
    versions
    []

let register name commands =
  let previous =
    try Protocol_hash.Table.find versions name
    with Not_found -> [] in
  Protocol_hash.Table.replace versions name (commands @ previous)

let commands_for_version version =
  try Protocol_hash.Table.find versions version
  with Not_found -> raise Version_not_found

let force_switch =
  Cli_entries.switch
    ~parameter:"-force"
    ~doc:"Take an action that will overwrite data.\
          This silences any warnings and some checks"
