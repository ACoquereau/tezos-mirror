(*****************************************************************************)
(*                                                                           *)
(* MIT License                                                               *)
(* Copyright (c) 2022 Nomadic Labs <contact@nomadic-labs.com>                *)
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

open Bls
open Identities
module L = Plompiler.LibCircuit
open Gates_common

(* Boolean check : checks that the first wire is boolean
   Non Arith
   degree : 3n
   nb identities : 1
   advice selectors : None
   equations : q·a·(1 - a)
*)
module BoolCheck : Base_sig = struct
  let q_label = "qbool"

  let identity = (q_label, 1)

  let index_com = None

  let nb_advs = 0

  let nb_buffers = 1

  let gx_composition = false

  let equations ~q ~a ~b:_ ~c:_ ~d:_ ~e:_ ~ag:_ ~bg:_ ~cg:_ ~dg:_ ~eg:_
      ?precomputed_advice:_ () =
    Scalar.[q * sub one a * a]

  let blinds = SMap.of_list [(left, [|1; 0|])]

  let prover_identities ~prefix_common ~prefix ~public:_ ~domain:_ evaluations =
    let tmps, ids = get_buffers ~nb_buffers ~nb_ids:(snd identity) in
    let ({q; a; _} : witness) =
      get_evaluations ~q_label ~blinds ~prefix ~prefix_common evaluations
    in

    let one_minus_a =
      Evaluations.linear_c
        ~res:tmps.(0)
        ~evaluations:[a]
        ~add_constant:one
        ~linear_coeffs:[mone]
        ()
    in
    let id =
      Evaluations.mul_c ~res:ids.(0) ~evaluations:[q; a; one_minus_a] ()
    in
    SMap.singleton (prefix @@ q_label ^ ".0") id

  let verifier_identities ~prefix_common ~prefix ~public:_ ~generator:_
      ~size_domain:_ _ answers =
    let q = get_answer answers X @@ prefix_common q_label in
    let a = get_answer answers X @@ prefix left in
    let res = Scalar.(q * a * sub one a) in
    SMap.singleton (prefix @@ q_label ^ ".0") res

  let polynomials_degree = SMap.of_list [(left, 3); (q_label, 3)]

  let cs ~q ~a ~b:_ ~c:_ ~d:_ ~e:_ ~ag:_ ~bg:_ ~cg:_ ~dg:_ ~eg:_
      ?precomputed_advice:_ () =
    let open L in
    map_singleton
      (let* tmp = Num.mul q a in
       let* tmp' = Num.add_constant Scalar.(one) a ~ql:mone in
       Num.mul tmp tmp')
end

(* Conditional swap : Depending on wire a, swap wires (b,c) in (d,e)
    Non Arith
    degree : 3n
    nb identities : 2
    advice selectors : None
    equations :
      q · [(1-a)·b + a·c - d]
      q · [a·b + (1-a)·c - e]
    /!\ We assume that wire a is a bit, this needs to be asserted independently
*)
module CondSwap : Base_sig = struct
  let q_label = "qcond_swap"

  let identity = (q_label, 2)

  let index_com = None

  let nb_advs = 0

  let nb_buffers = 4

  let gx_composition = false

  let equations ~q ~a:bit ~b ~c ~d ~e ~ag:_ ~bg:_ ~cg:_ ~dg:_ ~eg:_
      ?precomputed_advice:_ () =
    let bbit = Scalar.(sub one bit) in
    Scalar.
      [q * ((bbit * b) + sub (bit * c) d); q * ((bit * b) + sub (bbit * c) e)]

  let blinds =
    SMap.of_list
      [
        (left, [|1; 0|]);
        (right, [|1; 0|]);
        (output, [|1; 0|]);
        (top, [|1; 0|]);
        (bottom, [|1; 0|]);
      ]

  let prover_identities ~prefix_common ~prefix ~public:_ ~domain:_ evaluations =
    let tmps, ids = get_buffers ~nb_buffers ~nb_ids:(snd identity) in
    let ({q; a; b; c; d; e} : witness) =
      get_evaluations ~q_label ~blinds ~prefix ~prefix_common evaluations
    in
    let b, x, y, u, v = (a, b, c, d, e) in

    let bb =
      Evaluations.linear_c
        ~res:tmps.(0)
        ~evaluations:[b]
        ~add_constant:one
        ~linear_coeffs:[mone]
        ()
    in
    (* 0 = q · [(1 - bit) · x + bit · y - u] *)
    let t0 = Evaluations.mul_c ~res:tmps.(1) ~evaluations:[q; bb; x] () in
    let t1 = Evaluations.mul_c ~res:tmps.(2) ~evaluations:[q; b; y] () in
    let t2 = Evaluations.mul_c ~res:tmps.(3) ~evaluations:[q; u] () in
    let id1 =
      Evaluations.linear_c
        ~res:ids.(0)
        ~evaluations:[t0; t1; t2]
        ~linear_coeffs:[one; one; mone]
        ()
    in
    (* 0 = q · [bit · x + (1 - bit) · y - v] *)
    let t0 = Evaluations.mul_c ~res:tmps.(1) ~evaluations:[q; bb; y] () in
    let t1 = Evaluations.mul_c ~res:tmps.(2) ~evaluations:[q; b; x] () in
    let t2 = Evaluations.mul_c ~res:tmps.(3) ~evaluations:[q; v] () in
    let id2 =
      Evaluations.linear_c
        ~res:ids.(1)
        ~evaluations:[t0; t1; t2]
        ~linear_coeffs:[one; one; mone]
        ()
    in
    SMap.of_list
      [(prefix @@ q_label ^ ".0", id1); (prefix @@ q_label ^ ".1", id2)]

  let verifier_identities ~prefix_common ~prefix ~public:_ ~generator:_
      ~size_domain:_ : verifier_identities =
   fun _ answers ->
    let ({q; a; b; c; d; e; _} : answers) =
      get_answers ~q_label ~blinds ~prefix ~prefix_common answers
    in
    let bit, x, y, u, v = (a, b, c, d, e) in
    let bbit = Scalar.(sub one bit) in
    (* 0 = q · [(1 - bit) · x + bit       · y - u] *)
    let id1 = Scalar.(q * ((bbit * x) + sub (bit * y) u)) in
    (* 0 = q · [bit       · x + (1 - bit) · y - v] *)
    let id2 = Scalar.(q * ((bit * x) + sub (bbit * y) v)) in
    SMap.of_list
      [(prefix @@ q_label ^ ".0", id1); (prefix @@ q_label ^ ".1", id2)]

  let polynomials_degree =
    SMap.of_list
      [(q_label, 3); (left, 3); (right, 3); (output, 3); (top, 3); (bottom, 3)]

  let cs ~q:qbool ~a:bit ~b:x ~c:y ~d:u ~e:v ~ag:_ ~bg:_ ~cg:_ ~dg:_ ~eg:_
      ?precomputed_advice:_ () =
    let open L in
    let open Num in
    let* bit_times_x = mul bit x in
    let* bit_times_y = mul bit y in
    (* id1 = qbool · [(1 - b) · x + b · y - u] *)
    let* id1 =
      let* all =
        add_list
          ~coeffs:[one; mone; one; mone]
          (to_list [x; bit_times_x; bit_times_y; u])
      in
      mul qbool all
    in
    (* id1 = qbool · [b · x + (1 - b) · y - v] *)
    let* id2 =
      let* all =
        add_list
          ~coeffs:[one; one; mone; mone]
          (to_list [bit_times_x; y; bit_times_y; v])
      in
      mul qbool all
    in
    ret [id1; id2]
end
