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

let path = "eth"

let spawn_command command decode =
  let process = Process.spawn path command in
  let* output = Process.check_and_read_stdout process in
  return (JSON.parse ~origin:"eth_spawn_command" output |> decode)

let balance ~account ~endpoint =
  spawn_command ["address:balance"; account; "--network"; endpoint] JSON.as_int

let transaction_send ~source_private_key ~to_public_key ~value ~endpoint =
  spawn_command
    [
      "transaction:send";
      "--pk";
      source_private_key;
      "--to";
      to_public_key;
      "--value";
      Z.to_string value;
      "--network";
      endpoint;
    ]
    JSON.as_string

let get_block ~block_id ~endpoint =
  let exception Could_not_parse_block of string in
  let* answer =
    spawn_command ["block:get"; block_id; "--network"; endpoint] Fun.id
  in
  let block_as_json =
    match Data_encoding.Json.from_string (JSON.encode answer) with
    | Ok json -> json
    | Error msg -> raise @@ Could_not_parse_block msg
  in
  return @@ Data_encoding.Json.destruct Eth.Block.encoding block_as_json

let block_number ~endpoint =
  spawn_command ["block:number"; "--network"; endpoint] JSON.as_int
