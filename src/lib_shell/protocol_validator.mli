(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

type t

type protocol_error =
  | Compilation_failed
  | Dynlinking_failed

type error +=
  | Invalid_protocol of
      { hash: Protocol_hash.t ; error: protocol_error }

val create: Distributed_db.t -> t

val validate:
  t ->
  Protocol_hash.t -> Protocol.t ->
  State.Registred_protocol.t tzresult Lwt.t

val shutdown: t -> unit Lwt.t

val fetch_and_compile_protocol:
  t ->
  ?peer:P2p.Peer_id.t ->
  ?timeout:float ->
  Protocol_hash.t -> State.Registred_protocol.t tzresult Lwt.t

val fetch_and_compile_protocols:
  t ->
  ?peer:P2p.Peer_id.t ->
  ?timeout:float ->
  State.Block.t -> unit tzresult Lwt.t

val prefetch_and_compile_protocols:
  t ->
  ?peer:P2p.Peer_id.t ->
  ?timeout:float ->
  State.Block.t -> unit

