(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2023 Nomadic Labs <contact@nomadic-labs.com>                *)
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

open Tezos_scoru_wasm
open Tezos_lazy_containers
open Tezos_webassembly_interpreter
module Vector = Lazy_vector.Int32Vector

(** Call stack representation and construction. *)

(** The call stack computation algorithm is the following:

    There are two components: the current node (or stack frame) and the
    continuation (a list of stack frames). There's a "toplevel node" describing
    the execution at the toplevel of the interpreter.
    A node contains:
    - [id]: a function call representation (an identifier)
    - [t]: the ticks elapsed during the call
    - [sub]: the subcalls.

    The algorithm starts with an empty toplevel and an empty continuation.
    - on function call (id, current_tick, current_node, continuation):
    1. create a node N_id: (id, t: current_tick, sub:[])
    2. update current_node N_curr with t:(current_tick - t)
      => the number of ticks is now the diff between the moment the call started
          and the subcall started.
    3. push N_curr on the continuation
    4. return N_id, continuation

    - on function end (current_tick, current_node, continuation):
    1. update current_node N_curr with t:(current_tick - t)
    2. pop N_prev from the continuation
    3. update N_prev: t:(current_tick - t) sub:(sub + N_curr)
    4. return N_prev, continuation

    Let's take an example:
    call: f () { ...... g () { .... h () { ...... } .......... } ......... }
    tick: 0 ----------> 10 -------> 30 ---------> 60 --------> 100 -----> 160
          [  10 ticks  ] [ 20 ticks ] [ 30 ticks ] [ 40 ticks ] [ 60 ticks ]

    - `f` takes 10 + 60 = 70 ticks
    - `g` takes 20 + 40 = 60 ticks
    - `h` takes 30 ticks

    T ([nodes]) : toplevel
    K : continuation (list)
    N : current node (N(id) means it hasn't changed from previous step)

    N, K |- exec

    Start:
    T, [] |- f () { g () { h () { } } }
    ==> at tick 0
    N (f, 0, []), [T] |- g () { h () { } } }
    ==> at tick 10
    N (g, 10, []), [N (f, 10 - 0 = 10, []); T] |- h () { } } }
    ==> at tick 30
    N (h, 30, []), [N (g, 30 - 10 = 20, []); N(f); T] |- } } }
    ==> at tick 60
    N (g, 60 - 20 = 40, [N (h, 60 - 30 = 30, [])]), [N(f); T] |- } }
    ==> at tick 100
    N (f, 100 - 10 = 90, [N (g, 100 - 40 = 60, [N(h)])]), [T] |- }
    ==> at tick 160
    T [N (f, 160 - 90 = 70, [N(g, 60, [N(h, 30, [])])])], [] |- _

*)

type 'function_call call_stack =
  | Node of 'function_call * Z.t * 'function_call call_stack list
  | Toplevel of 'function_call call_stack list

(** [end_function_call current_tick current_function call_stack] implements an
    ending call. Please refer to the prelude of the file. *)
let end_function_call current_tick current_function call_stack =
  match current_function with
  | Node (call, starting_tick, subcalls) -> (
      let final_node =
        Node (call, Z.sub current_tick starting_tick, List.rev subcalls)
      in
      match call_stack with
      | [] -> assert false
      | Toplevel finalized :: stack ->
          (Toplevel (final_node :: finalized), stack)
      | Node (call, ticks, subcalls) :: stack ->
          (Node (call, Z.sub current_tick ticks, final_node :: subcalls), stack)
      )
  (* A toplevel call cannot reduce. *)
  | Toplevel _ -> (current_function, call_stack)

(** [call_function called_function current_tick current_function call_stack]
    implements a function start. Please refere to the prelude of the module. *)
let call_function called_function current_tick current_function call_stack =
  match current_function with
  | Toplevel _ as top ->
      let func = Node (called_function, current_tick, []) in
      (func, top :: call_stack)
  | Node (current_call, ticks, subcalls) ->
      let stack =
        Node (current_call, Z.sub current_tick ticks, subcalls) :: call_stack
      in
      let func = Node (called_function, current_tick, []) in
      (func, stack)

(** Profiling the execution of the PVM *)

(** A function call can be either a direct call, a call through a reference or
    an internal step of the PVM. *)
type function_call =
  | CallDirect of int32
  | CallRef of int32
  | Internal of string

let pp_call ppf = function
  | CallDirect i -> Format.fprintf ppf "function[%ld]" i
  | CallRef i -> Format.fprintf ppf "function_ref[%ld]" i
  | Internal s -> Format.fprintf ppf "%%interpreter(%s)" s

(** [initial_eval_call module_] creates the node with the correct identifier for
    `kernel_run` according to the profiled module. *)
let initial_eval_call (module_exports : Ast.export Vector.t) =
  let open Lwt_syntax in
  let+ exports = Vector.to_list module_exports in
  let var =
    List.find_map
      (function
        | {Source.it = {Ast.name; edesc = {it = Ast.FuncExport var; _}}; _}
          when name = Constants.wasm_entrypoint ->
            Some var
        | _ -> None)
      exports
  in
  match var with Some {it = id; _} -> CallDirect id | None -> assert false

(** [update_on_decode current_tick current_call_context] starts and stop
    `internal` calls related to the {Decode} step of the PVM. *)
let update_on_decode current_tick (current_node, call_stack) =
  let open Lwt_syntax in
  function
  | Decode.MKStart ->
      return_some
      @@ call_function (Internal "decode") current_tick current_node call_stack
  | Decode.MKStop _ ->
      let current_node, call_stack =
        end_function_call current_tick current_node call_stack
      in
      return_some
      @@ call_function (Internal "link") current_tick current_node call_stack
  | _ -> return_none

(** [update_on_link current_tick current_call_context] starts and stop
    `internal` call to the {Link} step of the PVM. *)
let update_on_link current_tick (current_node, call_stack) module_
    imports_offset =
  let open Lwt_syntax in
  if imports_offset >= Vector.num_elements module_.Source.it.Ast.imports then
    let current_node, call_stack =
      end_function_call current_tick current_node call_stack
    in
    return_some
    @@ call_function (Internal "init") current_tick current_node call_stack
  else return_none

(** [update_on_init current_tick current_call_context] starts and stop
    `internal` call to the {Init} step of the PVM. *)
let update_on_init current_tick (current_node, call_stack) module_ =
  let open Lwt_syntax in
  function
  | Eval.IK_Stop ->
      let current_node, call_stack =
        end_function_call current_tick current_node call_stack
      in
      let* start = initial_eval_call module_.Source.it.Ast.exports in
      return_some @@ call_function start current_tick current_node call_stack
  | _ -> return_none

(** [update_on_instr current_tick current_node call_stack] handle function calls
    during the evaluation. *)
let update_on_instr current_tick current_node call_stack = function
  | Eval.Plain (Ast.Call f) ->
      Lwt.return_some
        (call_function
           (CallDirect f.Source.it)
           current_tick
           current_node
           call_stack)
  | Eval.Plain (CallIndirect (f, _)) ->
      Lwt.return_some
        (call_function
           (CallRef f.Source.it)
           current_tick
           current_node
           call_stack)
  | _ -> Lwt.return_none

(** [update_on_eval current_tick current_call_context] handle function calls and
    end during the evaluation. *)
let update_on_eval current_tick (current_node, call_stack) =
  let open Lwt_syntax in
  function
  (* Instruction evaluation step *)
  | Eval.(SK_Next (_, _, LS_Start (Label_stack (label, _)))) ->
      let _, es = label.Eval.label_code in
      if 0l < Vector.num_elements es then
        let* e = Vector.get 0l es in
        update_on_instr current_tick current_node call_stack e.Source.it
      else return_none
  (* Labels `result` or `trapped` implies the end of a function call and the pop of
     the current stack frame, this can be interpreted as an end of the current
     function. *)
  | SK_Start ({frame_label_kont = Label_trapped _ | Label_result _; _}, _) ->
      return_some @@ end_function_call current_tick current_node call_stack
  (* An invocation of function that doesn't return a new stack frame implies the
     current function is an host function, and it is the end of its call. *)
  | SK_Next
      ( _,
        _,
        LS_Craft_frame
          (Label_stack (_, _), Inv_stop {fresh_frame = None; remaining_ticks; _})
      )
    when Z.equal Z.zero remaining_ticks ->
      return_some @@ end_function_call current_tick current_node call_stack
  | _ -> return_none

(** [update_call_stack current_tick current_context_call state] returns the call
    context changes for any state. Returns [None] if no change happened. *)
let update_call_stack current_tick (current_node, call_stack) state =
  let open Lwt_syntax in
  match state with
  | Wasm_pvm_state.Internal_state.Decode {Decode.module_kont; _} ->
      update_on_decode current_tick (current_node, call_stack) module_kont
  | Link {ast_module; imports_offset; _} ->
      update_on_link
        current_tick
        (current_node, call_stack)
        ast_module
        imports_offset
  | Init {init_kont; _} ->
      update_on_init current_tick (current_node, call_stack) init_kont
  | Eval {config = {step_kont; _}; _} ->
      update_on_eval current_tick (current_node, call_stack) step_kont
  | _ -> return_none

(** [eval_and_profile ?write_debug ?reveal_builtins tree] profiles a kernel up
    to the next result, and returns the call stack. *)
let eval_and_profile ?write_debug ?reveal_builtins tree =
  let open Lwt_syntax in
  (* The call context is built as a side effect of the evaluation. *)
  let call_stack = ref (Toplevel [], []) in

  let compute_and_snapshot pvm_state =
    let* updated_stack =
      update_call_stack
        pvm_state.Wasm_pvm_state.Internal_state.current_tick
        !call_stack
        pvm_state.tick_state
    in
    Option.iter
      (fun (current_node, current_call_stack) ->
        call_stack := (current_node, current_call_stack))
      updated_stack ;

    let* input_request_val = Wasm_vm.get_info pvm_state in
    match (input_request_val.input_request, pvm_state.tick_state) with
    | Reveal_required _, _ when reveal_builtins = None -> return_false
    | Input_required, _ | Reveal_required _, _ -> return_false
    | _ -> return_true
  in
  let rec eval_until_input_requested accumulated_ticks tree =
    let* pvm_state =
      Encodings_util.Tree_encoding_runner.decode
        Wasm_pvm.pvm_state_encoding
        tree
    in
    let* info = Wasm_utils.Wasm.get_info tree in
    match info.Wasm_pvm_state.input_request with
    | No_input_required ->
        let* tree, ticks =
          Wasm_utils.Wasm.Internal_for_tests.compute_step_many_until
            ?write_debug
            ?reveal_builtins
            ~max_steps:(Z.to_int64 pvm_state.max_nb_ticks)
            compute_and_snapshot
            tree
        in
        eval_until_input_requested
          (Z.add accumulated_ticks @@ Z.of_int64 ticks)
          tree
    | Input_required | Reveal_required _ -> return (tree, accumulated_ticks)
  in
  let+ tree, ticks = eval_until_input_requested Z.zero tree in
  let call_stack =
    match !call_stack with
    | Toplevel l, stack -> (Toplevel (List.rev l), stack)
    | n -> n
  in
  (tree, ticks, call_stack)
