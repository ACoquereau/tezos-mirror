(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022-2023 Trili Tech  <contact@trili.tech>                  *)
(*                                                                           *)
(* Permission is hereby granted, free of charge, to any person obtaining a   *)
(* copy of this software and associated documentation files (the "Software"),*)
(* to deal in the Software without restriction, including without limitation *)
(* the rights to use, copy, modify, merge, publish, distribute, sublicense,  *)
(* and/or sell copies of the Software, and to permit persons to whom the     *)
(* Software is furnished to do so, subject to the following conditions:      *)
(*                                                                           *)
(* The above copyright notice and this permission notice shall be included   *)
(* in all copies or substantial portions of the Software.                    *)
(*                                                                           *)
(* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR*)
(* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,  *)
(* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL   *)
(* THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER*)
(* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING   *)
(* FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER       *)
(* DEALINGS IN THE SOFTWARE.                                                 *)
(*                                                                           *)
(*****************************************************************************)

(** DAC pages encoding schemes *)

type error +=
  | Payload_cannot_be_empty
  | Cannot_serialize_page_payload
  | Cannot_deserialize_page
  | Non_positive_size_of_payload
  | Merkle_tree_branching_factor_not_high_enough
  | Cannot_combine_pages_data_of_different_type
  | Hashes_page_repr_expected_single_element

(* Encoding scheme configuration. *)
module type CONFIG = sig
  val max_page_size : int
end

type version = int

(* Versioning to configure content and hash serialization. *)
module type VERSION = sig
  val content_version : version

  val hashes_version : version
end

(** [Dac_codec] is a module for encoding a payload as a whole and returnining
    the calculated root hash.
*)
module type Dac_codec = sig
  (* Page store type *)
  type page_store

  (** [serialize_payload page_store payload] serializes a [payload] into pages
      suitable to be read by a PVM's `reveal_preimage` and stores it into
      [page_store]. The serialization scheme  is some hash-based encoding
      scheme such that a root hash is produced that represents the payload.
  *)
  val serialize_payload :
    Dac_plugin.t ->
    page_store:page_store ->
    bytes ->
    Dac_plugin.hash tzresult Lwt.t

  (** [deserialize_payload dac_plugin page_store hash] deserializes a payload from [hash]
      using some hash-based encoding scheme. Any payload serialized by
      [serialize_payload] can de deserialized from its root hash by
      [deserialize_payload], that is, these functions are inverses of each
      other.
  *)
  val deserialize_payload :
    Dac_plugin.t ->
    page_store:page_store ->
    Dac_plugin.hash ->
    bytes tzresult Lwt.t
end

(** [Buffered_dac_codec] partially constructs a Dac external message payload by
    aggregating  messages one message at a time. [add] maintains partially
    constructed pages in a buffer [t] and persist full pages to [page_store].
    [finalize] is called to end the aggeragation process and calculate the
    resulting root hash.
*)
module type Buffered_dac_codec = sig
  (* Buffer type *)
  type t

  (* Page store type *)
  type page_store

  (* Returns an empty buffer *)
  val empty : unit -> t

  (** [add dac_plugin page_store buffer message] adds a [message] to [buffer]. The
      [buffer] is serialized to [page_store] when it is full. Serialization
      logic is dependent on the encoding scheme.
  *)
  val add :
    Dac_plugin.t -> page_store:page_store -> t -> bytes -> unit tzresult Lwt.t

  (** [finalize dac_plugin page_store buffer] serializes the [buffer] to [page_store] and
      returns a root hash that represents the final payload. The serialization
      logic is dependent on the encoding scheme. [buffer] is emptied after
      this call.
  *)
  val finalize :
    Dac_plugin.t -> page_store:page_store -> t -> Dac_plugin.hash tzresult Lwt.t

  (** [deserialize_payload dac_plugin page_store hash] deserializes a payload from [hash]
      using some hash-based encoding scheme. Any payload serialized by [add] +
      [finalize] can be deserialized by this function.
  *)
  val deserialize_payload :
    Dac_plugin.t ->
    page_store:page_store ->
    Dac_plugin.hash ->
    bytes tzresult Lwt.t
end

(** Encoding of DAC payload as a Merkle tree with an arbitrary branching
    factor greater or equal to 2. The serialization process works as follows:
    {ul
      {li A large sequence of bytes, the payload, is split into several pages
          of fixed size, each of which is prefixed with a small sequence
          of bytes (also of fixed size), which is referred to as the preamble
          of the page. Pages obtained directly from the original payload
          are referred to as `Contents pages`. Contents pages constitute the
          leaves of the Merkle tree being built,
      }
      {li Each content page (each of which is a sequence of bytes consisting
        of the preamble followed by the actual content from the original
        payload) is then hashed. The size of each hash is fixed. The hashes are
        concatenated together, and the resulting sequence of bytes is split
        into pages of the same size of `Hashes pages`, each of which is
        prefixed with a preamble whose size is the same as in Contents pages.
        Hashes pages correspond to nodes of the Merkle tree being built, and
        the children of a hash page are the (either Payload or Hashes) pages
        whose hash appear into the former,
      }
      {li Hashes pages are hashed using the same process described above, leading
        to a smaller list of hashes pages. To guarantee that the list of hashes
        pages is actually smaller than the original list of pages being hashed,
        we require the size of pages to be large enough to contain at least two
        hashes.
      }
    }

    Merkle tree encodings of DAC pages are versioned, to allow for multiple
    hashing schemes to be used.
 *)
module Merkle_tree : sig
  module V0 : sig
    module Filesystem : Dac_codec with type page_store = Page_store.Filesystem.t

    module Remote : Dac_codec with type page_store = Page_store.Remote.t
  end

  (**/**)

  module Internal_for_tests : sig
    module Make_buffered (S : Page_store.S) (V : VERSION) (C : CONFIG) :
      Buffered_dac_codec with type page_store = S.t

    module Make (B : Buffered_dac_codec) :
      Dac_codec with type page_store := B.page_store
  end
end

(** Encoding of DAC payload as a Hash Chain/Merkle List. The encoding implementation
    is specific to the Arith PVM.
 *)
module Hash_chain : sig
  module V0 : sig
    val serialize_payload :
      Dac_plugin.t ->
      for_each_page:(Dac_plugin.hash * bytes -> unit tzresult Lwt.t) ->
      bytes ->
      Dac_plugin.hash tzresult Lwt.t

    val make_hash_chain :
      Dac_plugin.t -> bytes -> ((Dac_plugin.hash * bytes) list, 'a) result
  end
end
