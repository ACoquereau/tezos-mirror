(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

(** Tezos Shell - Network message for the gossip P2P protocol. *)

type t =

  | Get_current_branch of Net_id.t
  | Current_branch of Net_id.t * Block_locator.t
  | Deactivate of Net_id.t

  | Get_current_head of Net_id.t
  | Current_head of Net_id.t * Block_header.t * Mempool.t

  | Get_block_headers of Block_hash.t list
  | Block_header of Block_header.t

  | Get_operations of Operation_hash.t list
  | Operation of Operation.t

  | Get_protocols of Protocol_hash.t list
  | Protocol of Protocol.t

  | Get_operation_hashes_for_blocks of (Block_hash.t * int) list
  | Operation_hashes_for_block of
      Block_hash.t * int *
      Operation_hash.t list * Operation_list_list_hash.path

  | Get_operations_for_blocks of (Block_hash.t * int) list
  | Operations_for_block of
      Block_hash.t * int *
      Operation.t list * Operation_list_list_hash.path

val cfg : t P2p.message_config

val pp_json : Format.formatter -> t -> unit
