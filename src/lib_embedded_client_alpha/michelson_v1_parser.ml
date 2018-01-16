(**************************************************************************)
(*                                                                        *)
(*    Copyright (c) 2014 - 2017.                                          *)
(*    Dynamic Ledger Solutions, Inc. <contact@tezos.com>                  *)
(*                                                                        *)
(*    All rights reserved. No warranty, explicit or implicit, provided.   *)
(*                                                                        *)
(**************************************************************************)

open Tezos_micheline
open Micheline_parser
open Micheline

type parsed =
  { source : string ;
    unexpanded : string canonical ;
    expanded : Michelson_v1_primitives.prim canonical ;
    expansion_table : (int * (Micheline_parser.location * int list)) list ;
    unexpansion_table : (int * int) list }

(* Unexpanded toplevel expression should be a sequence *)
let expand_all source ast errors =
  let unexpanded, loc_table =
    extract_locations ast in
  let rec error_map (expanded, errors) f = function
    | [] -> (List.rev expanded, List.rev errors)
    | hd :: tl ->
        let (new_expanded, new_errors) = f hd in
        error_map
          (new_expanded :: expanded, List.rev_append new_errors errors)
          f tl in
  let error_map = error_map ([], []) in
  let rec expand expr =
    match Michelson_macros.expand expr with
    | Ok expanded ->
        begin
          match expanded with
          | Seq (loc, items, annot) ->
              let items, errors = error_map expand items in
              (Seq (loc, items, annot), errors)
          | Prim (loc, name, args, annot) ->
              let args, errors = error_map expand args in
              (Prim (loc, name, args, annot), errors)
          | Int _ | String _ as atom -> (atom, []) end
    | Error errors -> (expr, errors) in
  let expanded, expansion_errors = expand (root unexpanded) in
  let expanded, unexpansion_table =
    extract_locations expanded in
  let expansion_table =
    let sorted =
      List.sort (fun (_, a) (_, b) -> compare a b) unexpansion_table in
    let grouped =
      let rec group = function
        | acc, [] -> acc
        | [], (u, e) :: r ->
            group ([ (e, [ u ]) ], r)
        | ((pe, us) :: racc as acc), (u, e) :: r ->
            if e = pe then
              group (((e, u :: us) :: racc), r)
            else
              group (((e, [ u ]) :: acc), r) in
      group ([], sorted) in
    List.map2
      (fun (l, ploc) (l', elocs) ->
         assert (l = l') ;
         (l, (ploc, elocs)))
      (List.sort compare loc_table)
      (List.sort compare grouped) in
  match Environment.wrap_error (Michelson_v1_primitives.prims_of_strings expanded) with
  | Ok expanded ->
      { source ; unexpanded ; expanded ;
        expansion_table ; unexpansion_table },
      errors @ expansion_errors
  | Error errs ->
      { source ; unexpanded ;
        expanded = Micheline.strip_locations (Seq ((), [], None)) ;
        expansion_table ; unexpansion_table },
      errs @ errors @ expansion_errors

let parse_toplevel ?check source =
  let tokens, lexing_errors = Micheline_parser.tokenize source in
  let asts, parsing_errors = Micheline_parser.parse_toplevel ?check tokens in
  let ast = match asts with
    | [ ast ] -> ast
    | asts ->
        let start = min_point asts and stop = max_point asts in
        Seq ({ start ; stop }, asts, None) in
  expand_all source ast (lexing_errors @ parsing_errors)

let parse_expression ?check source =
  let tokens, lexing_errors = Micheline_parser.tokenize source in
  let ast, parsing_errors = Micheline_parser.parse_expression ?check tokens in
  expand_all source ast (lexing_errors @ parsing_errors)

let expand_all ~source ~original =
  expand_all source original []
