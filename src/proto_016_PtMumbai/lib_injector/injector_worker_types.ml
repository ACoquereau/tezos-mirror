(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2022 Nomadic Labs, <contact@nomadic-labs.com>               *)
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

open Injector_common
open Injector_sigs

module Request (L1_operation : INJECTOR_OPERATION) = struct
  type ('a, 'b) t =
    | Add_pending : L1_operation.t -> (unit, error trace) t
    | New_tezos_head :
        (Block_hash.t * int32) * (Block_hash.t * int32) reorg
        -> (unit, error trace) t
    | Inject : (unit, error trace) t

  type view = View : _ t -> view

  let view req = View req

  let encoding =
    let open Data_encoding in
    union
      [
        case
          (Tag 0)
          ~title:"Add_pending"
          (merge_objs
             (obj1 (req "request" (constant "add_pending")))
             L1_operation.encoding)
          (function View (Add_pending op) -> Some ((), op) | _ -> None)
          (fun ((), op) -> View (Add_pending op));
        case
          (Tag 1)
          ~title:"New_tezos_head"
          (let block_level =
             obj2 (req "block" Block_hash.encoding) (req "level" int32)
           in
           obj3
             (req "request" (constant "new_tezos_head"))
             (req "head" block_level)
             (req "reorg" (reorg_encoding block_level)))
          (function
            | View (New_tezos_head (b, r)) -> Some ((), b, r) | _ -> None)
          (fun ((), b, r) -> View (New_tezos_head (b, r)));
        case
          (Tag 2)
          ~title:"Inject"
          (obj1 (req "request" (constant "inject")))
          (function View Inject -> Some () | _ -> None)
          (fun () -> View Inject);
      ]

  let pp ppf (View r) =
    match r with
    | Add_pending op ->
        Format.fprintf ppf "request add %a to pending queue" L1_operation.pp op
    | New_tezos_head ((block, level), r) ->
        Format.fprintf
          ppf
          "switching to new Tezos head %a at level %ld"
          Block_hash.pp
          block
          level ;
        if r.old_chain <> [] || r.new_chain <> [] then
          Format.fprintf
            ppf
            ", with reorg of -%d +%d"
            (List.length r.old_chain)
            (List.length r.new_chain)
    | Inject -> Format.fprintf ppf "injection"
end

module Name = struct
  type t = Signature.public_key_hash

  let encoding = Tezos_crypto.Signature.Public_key_hash.encoding

  let base = ["injector"]

  let pp = Tezos_crypto.Signature.Public_key_hash.pp_short

  let equal = Tezos_crypto.Signature.Public_key_hash.equal
end
