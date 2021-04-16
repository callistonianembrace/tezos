(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2021 Nomadic Labs <contact@nomadic-labs.com>                *)
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

(** Testing
    -------
    Component:  Protocol (baking)
    Invocation: dune exec src/proto_alpha/lib_protocol/test/main.exe -- test "^level module$"
    Subject:    some functions in the Level module
*)

open Protocol

let test_case_1 =
  ( [ Level_repr.
        {
          first_level = Raw_level_repr.of_int32_exn 1l;
          blocks_per_cycle = 8l;
          blocks_per_commitment = 2l;
        } ],
    [ (1, (1, 0, 0, 0, false));
      (2, (2, 1, 0, 1, true));
      (3, (3, 2, 0, 2, false));
      (8, (8, 7, 0, 7, true));
      (9, (9, 8, 1, 0, false));
      (16, (16, 15, 1, 7, true));
      (17, (17, 16, 2, 0, false));
      (64, (64, 63, 7, 7, true));
      (65, (65, 64, 8, 0, false)) ] )

let test_case_2 =
  ( [ Level_repr.
        {
          first_level = Raw_level_repr.of_int32_exn 1l;
          blocks_per_cycle = 8l;
          blocks_per_commitment = 2l;
        };
      {
        first_level = Raw_level_repr.of_int32_exn 17l;
        blocks_per_cycle = 16l;
        blocks_per_commitment = 4l;
      } ],
    [ (1, (1, 0, 0, 0, false));
      (2, (2, 1, 0, 1, true));
      (3, (3, 2, 0, 2, false));
      (8, (8, 7, 0, 7, true));
      (9, (9, 8, 1, 0, false));
      (16, (16, 15, 1, 7, true));
      (17, (17, 16, 2, 0, false));
      (32, (32, 31, 2, 15, true));
      (33, (33, 32, 3, 0, false));
      (64, (64, 63, 4, 15, true));
      (65, (65, 64, 5, 0, false)) ] )

let test_case_3 =
  ( [ Level_repr.
        {
          first_level = Raw_level_repr.of_int32_exn 1l;
          blocks_per_cycle = 8l;
          blocks_per_commitment = 2l;
        };
      {
        first_level = Raw_level_repr.of_int32_exn 17l;
        blocks_per_cycle = 16l;
        blocks_per_commitment = 4l;
      };
      {
        first_level = Raw_level_repr.of_int32_exn 49l;
        blocks_per_cycle = 6l;
        blocks_per_commitment = 3l;
      } ],
    [ (1, (1, 0, 0, 0, false));
      (2, (2, 1, 0, 1, true));
      (3, (3, 2, 0, 2, false));
      (8, (8, 7, 0, 7, true));
      (9, (9, 8, 1, 0, false));
      (16, (16, 15, 1, 7, true));
      (17, (17, 16, 2, 0, false));
      (32, (32, 31, 2, 15, true));
      (33, (33, 32, 3, 0, false));
      (48, (48, 47, 3, 15, true));
      (49, (49, 48, 4, 0, false));
      (64, (64, 63, 6, 3, false));
      (65, (65, 64, 6, 4, false));
      (66, (66, 65, 6, 5, true));
      (67, (67, 66, 7, 0, false)) ] )

let test_level_from_raw () =
  let cnt = ref 0 in
  List.iter_es
    (fun (cycle_eras, test_cases) ->
      incr cnt ;
      Format.printf "\ntest %d\n" !cnt ;
      List.iter_es
        (fun ( input_level,
               ( level,
                 level_position,
                 cycle,
                 cycle_position,
                 expected_commitment ) ) ->
          let raw_level =
            Raw_level_repr.of_int32_exn (Int32.of_int input_level)
          in
          let level_from_raw =
            Protocol.Level_repr.level_from_raw ~cycle_eras raw_level
          in
          Format.printf "level %d\n" input_level ;
          Assert.equal_int
            ~loc:__LOC__
            (Int32.to_int (Raw_level_repr.to_int32 level_from_raw.level))
            level
          >>=? fun () ->
          Assert.equal_int
            ~loc:__LOC__
            (Int32.to_int level_from_raw.level_position)
            level_position
          >>=? fun () ->
          Assert.equal_int
            ~loc:__LOC__
            (Int32.to_int (Cycle_repr.to_int32 level_from_raw.cycle))
            cycle
          >>=? fun () ->
          Assert.equal_int
            ~loc:__LOC__
            (Int32.to_int level_from_raw.cycle_position)
            cycle_position
          >>=? fun () ->
          Assert.equal_bool
            ~loc:__LOC__
            level_from_raw.expected_commitment
            expected_commitment)
        test_cases)
    [test_case_1; test_case_2; test_case_3]

let tests = [Test_services.tztest "level_from_raw" `Quick test_level_from_raw]
