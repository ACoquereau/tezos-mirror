(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

(* Tezos Command line interface - Local Storage for Configuration *)

open Lwt.Infix
open Cli_entries

module type Entity = sig
  type t
  val encoding : t Data_encoding.t
  val of_source :
    #Client_commands.wallet ->
    string -> t tzresult Lwt.t
  val to_source :
    #Client_commands.wallet ->
    t -> string tzresult Lwt.t
  val name : string
end

module type Alias = sig
  type t
  type fresh_param
  val load :
    #Client_commands.wallet ->
    (string * t) list tzresult Lwt.t
  val set :
    #Client_commands.wallet ->
    (string * t) list ->
    unit tzresult Lwt.t
  val find :
    #Client_commands.wallet ->
    string -> t tzresult Lwt.t
  val find_opt :
    #Client_commands.wallet ->
    string -> t option tzresult Lwt.t
  val rev_find :
    #Client_commands.wallet ->
    t -> string option tzresult Lwt.t
  val name :
    #Client_commands.wallet ->
    t -> string tzresult Lwt.t
  val mem :
    #Client_commands.wallet ->
    string -> bool tzresult Lwt.t
  val add :
    force:bool ->
    #Client_commands.wallet ->
    string -> t -> unit tzresult Lwt.t
  val del :
    #Client_commands.wallet ->
    string -> unit tzresult Lwt.t
  val update :
    #Client_commands.wallet ->
    string -> t -> unit tzresult Lwt.t
  val of_source :
    #Client_commands.wallet ->
    string -> t tzresult Lwt.t
  val to_source :
    #Client_commands.wallet ->
    t -> string tzresult Lwt.t
  val alias_param :
    ?name:string ->
    ?desc:string ->
    ('a, (#Client_commands.wallet as 'b), 'ret) Cli_entries.params ->
    (string * t -> 'a, 'b, 'ret) Cli_entries.params
  val fresh_alias_param :
    ?name:string ->
    ?desc:string ->
    ('a, (< .. > as 'obj), 'ret) Cli_entries.params ->
    (fresh_param -> 'a, 'obj, 'ret) Cli_entries.params
  val of_fresh :
    #Client_commands.wallet ->
    bool ->
    fresh_param ->
    string tzresult Lwt.t
  val source_param :
    ?name:string ->
    ?desc:string ->
    ('a, (#Client_commands.wallet as 'obj), 'ret) Cli_entries.params ->
    (t -> 'a, 'obj, 'ret) Cli_entries.params
  val autocomplete:
    #Client_commands.wallet -> string list tzresult Lwt.t
end

module Alias = functor (Entity : Entity) -> struct

  open Client_commands

  let wallet_encoding : (string * Entity.t) list Data_encoding.encoding =
    let open Data_encoding in
    list (obj2
            (req "name" string)
            (req "value" Entity.encoding))

  let load (wallet : #wallet) =
    wallet#load Entity.name ~default:[] wallet_encoding

  let set (wallet : #wallet) entries =
    wallet#write Entity.name entries wallet_encoding


  let autocomplete wallet =
    load wallet >>= function
    | Error _ -> return []
    | Ok list -> return (List.map fst list)

  let find_opt (wallet : #wallet) name =
    load wallet >>=? fun list ->
    try return (Some (List.assoc name list))
    with Not_found -> return None

  let find (wallet : #wallet) name =
    load wallet >>=? fun list ->
    try return (List.assoc name list)
    with Not_found ->
      failwith "no %s alias named %s" Entity.name name

  let rev_find (wallet : #wallet) v =
    load wallet >>=? fun list ->
    try return (Some (List.find (fun (_, v') -> v = v') list |> fst))
    with Not_found -> return None

  let mem (wallet : #wallet) name =
    load wallet >>=? fun list ->
    try
      ignore (List.assoc name list) ;
      return true
    with
    | Not_found -> return false

  let add ~force (wallet : #wallet) name value =
    let keep = ref false in
    load wallet >>=? fun list ->
    begin
      if force then
        return ()
      else
        iter_s (fun (n, v) ->
            if n = name && v = value then begin
              keep := true ;
              return ()
            end else if n = name && v <> value then begin
              failwith
                "another %s is already aliased as %s, \
                 use -force to update"
                Entity.name n
            end else if n <> name && v = value then begin
              failwith
                "this %s is already aliased as %s, \
                 use -force to insert duplicate"
                Entity.name n
            end else begin
              return ()
            end)
          list
    end >>=? fun () ->
    let list = List.filter (fun (n, _) -> n <> name) list in
    let list = (name, value) :: list in
    if !keep then
      return ()
    else
      wallet#write Entity.name list wallet_encoding

  let del (wallet : #wallet) name =
    load wallet >>=? fun list ->
    let list = List.filter (fun (n, _) -> n <> name) list in
    wallet#write Entity.name list wallet_encoding

  let update (wallet : #wallet) name value =
    load wallet >>=? fun list ->
    let list =
      List.map
        (fun (n, v) -> (n, if n = name then value else v))
        list in
    wallet#write Entity.name list wallet_encoding

  let save wallet list =
    wallet#write Entity.name wallet_encoding list

  include Entity

  let alias_param
      ?(name = "name") ?(desc = "existing " ^ Entity.name ^ " alias") next =
    param ~name ~desc
      (parameter (fun (cctxt : #Client_commands.wallet) s ->
           find cctxt s >>=? fun v ->
           return (s, v)))
      next

  type fresh_param = Fresh of string

  let of_fresh (wallet : #wallet) force (Fresh s) =
    load wallet >>=? fun list ->
    begin if force then
        return ()
      else
        iter_s
          (fun (n, _v) ->
             if n = s then
               Entity.to_source wallet _v >>=? fun value ->
               failwith
                 "@[<v 2>The %s alias %s already exists.@,\
                  The current value is %s.@,\
                  Use -force to update@]"
                 Entity.name n
                 value
             else
               return ())
          list
    end >>=? fun () ->
    return s

  let fresh_alias_param
      ?(name = "new") ?(desc = "new " ^ Entity.name ^ " alias") next =
    param ~name ~desc
      (parameter (fun (_ : < .. >) s -> return @@ Fresh s))
      next

  let source_param ?(name = "src") ?(desc = "source " ^ Entity.name) next =
    let desc =
      desc ^ "\n"
      ^ "can be an alias, file or literal (autodetected in this order)\n\
         use 'file:path', 'text:literal' or 'alias:name' to force" in
    param ~name ~desc
      (parameter (fun cctxt s ->
           let read path =
             Lwt.catch
               (fun () ->
                  Lwt_io.(with_file ~mode:Input path read) >>= fun content ->
                  return content)
               (fun exn ->
                  failwith
                    "cannot read file (%s)" (Printexc.to_string exn))
             >>=? fun content ->
             of_source cctxt content in
           begin
             match String.split ~limit:1 ':' s with
             | [ "alias" ; alias ]->
                 find cctxt alias
             | [ "text" ; text ] ->
                 of_source cctxt text
             | [ "file" ; path ] ->
                 read path
             | _ ->
                 find cctxt s >>= function
                 | Ok v -> return v
                 | Error a_errs ->
                     read s >>= function
                     | Ok v -> return v
                     | Error r_errs ->
                         of_source cctxt s >>= function
                         | Ok v -> return v
                         | Error s_errs ->
                             let all_errs =
                               List.flatten [ a_errs ; r_errs ; s_errs ] in
                             Lwt.return (Error all_errs)
           end))
      next

  let name (wallet : #wallet) d =
    rev_find wallet d >>=? function
    | None -> Entity.to_source wallet d
    | Some name -> return name

end
