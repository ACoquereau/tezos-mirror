(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

include Logging.Make(struct let name = "node.validator" end)

type t = {

  state: State.t ;
  db: Distributed_db.t ;
  block_validator: Block_validator.t ;
  timeout: Net_validator.timeout ;

  valid_block_input: State.Block.t Lwt_watcher.input ;
  active_nets: Net_validator.t Lwt.t Net_id.Table.t ;

}

let create state db timeout =
  let block_validator =
    Block_validator.create
      ~protocol_timeout:timeout.Net_validator.protocol
      db in
  let valid_block_input = Lwt_watcher.create_input () in
  { state ; db ; timeout ; block_validator ;
    valid_block_input ;
    active_nets = Net_id.Table.create 7 ;
  }

let activate v ?bootstrap_threshold ?max_child_ttl net_state =
  let net_id = State.Net.id net_state in
  lwt_log_notice "activate network %a" Net_id.pp net_id >>= fun () ->
  try Net_id.Table.find v.active_nets net_id
  with Not_found ->
    let nv =
      Net_validator.create
        ?bootstrap_threshold
        ?max_child_ttl
        v.timeout v.block_validator v.valid_block_input v.db net_state in
    Net_id.Table.add v.active_nets net_id nv ;
    nv

let get_exn { active_nets } net_id =
  Net_id.Table.find active_nets net_id

type error +=
  | Inactive_network of Net_id.t

let () =
  register_error_kind `Branch
    ~id: "node.validator.inactive_network"
    ~title: "Inactive network"
    ~description: "Attempted validation of a block from an inactive network."
    ~pp: (fun ppf net ->
        Format.fprintf ppf
          "Tried to validate a block from network %a, \
           that is not currently considered active."
          Net_id.pp net)
    Data_encoding.(obj1 (req "inactive_network" Net_id.encoding))
    (function Inactive_network net -> Some net | _ -> None)
    (fun net -> Inactive_network net)

let get v net_id =
  try get_exn v net_id >>= fun nv -> return nv
  with Not_found -> fail (Inactive_network net_id)

let validate_block v ?(force = false) ?net_id bytes operations =
  let hash = Block_hash.hash_bytes [bytes] in
  match Block_header.of_bytes bytes with
  | None -> failwith "Cannot parse block header."
  | Some block ->
      begin
        match net_id with
        | None -> begin
            Distributed_db.read_block_header
              v.db block.shell.predecessor >>= function
            | None ->
                failwith "Unknown predecessor (%a), cannot inject the block."
                  Block_hash.pp_short block.shell.predecessor
            | Some (net_id, _bh) -> get v net_id
          end
        | Some net_id ->
            get v net_id >>=? fun nv ->
            if force then
              return nv
            else
              Distributed_db.Block_header.known
                (Net_validator.net_db nv)
                block.shell.predecessor >>= function
              | true ->
                  return nv
              | false ->
                  failwith "Unknown predecessor (%a), cannot inject the block."
                    Block_hash.pp_short block.shell.predecessor
      end >>=? fun nv ->
      let validation =
        Net_validator.validate_block nv ~force hash block operations in
      return (hash, validation)

let shutdown { active_nets ; block_validator } =
  let jobs =
    Block_validator.shutdown block_validator ::
    Net_id.Table.fold
      (fun _ nv acc -> (nv >>= Net_validator.shutdown) :: acc)
      active_nets [] in
  Lwt.join jobs >>= fun () ->
  Lwt.return_unit

let watcher { valid_block_input } =
  Lwt_watcher.create_stream valid_block_input

let inject_operation v ?(force = false) ?net_id op =
  begin
    match net_id with
    | None -> begin
        Distributed_db.read_block_header
          v.db op.Operation.shell.branch >>= function
        | None ->
            failwith "Unknown branch (%a), cannot inject the operation."
              Block_hash.pp_short op.shell.branch
        | Some (net_id, _bh) -> get v net_id
      end
    | Some net_id ->
        get v net_id >>=? fun nv ->
        if force then
          return nv
        else
          Distributed_db.Block_header.known
            (Net_validator.net_db nv)
            op.shell.branch >>= function
          | true ->
              return nv
          | false ->
              failwith "Unknown branch (%a), cannot inject the operation."
                Block_hash.pp_short op.shell.branch
  end >>=? fun nv ->
  let pv = Net_validator.prevalidator nv in
  Prevalidator.inject_operation pv ~force op
