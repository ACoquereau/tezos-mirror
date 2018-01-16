(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

let group =
  { Cli_entries.name = "protocols" ;
    title = "Commands for managing protocols" }

let commands () =
  let open Cli_entries in
  let check_dir _ dn =
    if Sys.is_directory dn then
      return dn
    else
      failwith "%s is not a directory" dn in
  let check_dir_parameter = parameter check_dir in
  [

    command ~group ~desc: "list known protocols"
      no_options
      (prefixes [ "list" ; "protocols" ] stop)
      (fun () (cctxt : Client_commands.full_context) ->
         Client_node_rpcs.Protocols.list cctxt ~contents:false () >>=? fun protos ->
         Lwt_list.iter_s (fun (ph, _p) -> cctxt#message "%a" Protocol_hash.pp ph) protos >>= fun () ->
         return ()
      );

    command ~group ~desc: "inject a new protocol to the shell database"
      no_options
      (prefixes [ "inject" ; "protocol" ]
       @@ param ~name:"dir" ~desc:"directory containing a protocol" check_dir_parameter
       @@ stop)
      (fun () dirname (cctxt : Client_commands.full_context) ->
         Lwt.catch
           (fun () ->
              let _hash, proto = Protocol.read_dir dirname in
              Client_node_rpcs.inject_protocol cctxt proto >>= function
              | Ok hash ->
                  cctxt#message "Injected protocol %a successfully" Protocol_hash.pp_short hash >>= fun () ->
                  return ()
              | Error err ->
                  cctxt#error "Error while injecting protocol from %s: %a"
                    dirname Error_monad.pp_print_error err >>= fun () ->
                  return ())
           (fun exn ->
              cctxt#error "Error while injecting protocol from %s: %a"
                dirname Error_monad.pp_print_error [Error_monad.Exn exn] >>= fun () ->
              return ())
      );

    command ~group ~desc: "dump a protocol from the shell database"
      no_options
      (prefixes [ "dump" ; "protocol" ]
       @@ Protocol_hash.param ~name:"protocol hash" ~desc:""
       @@ stop)
      (fun () ph (cctxt : Client_commands.full_context) ->
         Client_node_rpcs.Protocols.contents cctxt ph >>=? fun proto ->
         Protocol.write_dir (Protocol_hash.to_short_b58check ph) ~hash:ph proto >>= fun () ->
         cctxt#message "Extracted protocol %a" Protocol_hash.pp_short ph >>= fun () ->
         return ()
      ) ;
  ]
