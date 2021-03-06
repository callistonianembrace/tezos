(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
(* Copyright (c) 2020 Metastate AG <hello@metastate.dev>                     *)
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

open Alpha_context
open Script_typed_ir

let empty : type a. a comparable_ty -> a set =
 fun ty ->
  let module OPS = Set.Make (struct
    type t = a

    let compare = Script_comparable.compare_comparable ty
  end) in
  (module struct
    type elt = a

    let elt_ty = ty

    module OPS = OPS

    let boxed = OPS.empty

    let size = 0
  end)

let update : type a. a -> bool -> a set -> a set =
 fun v b (module Box) ->
  (module struct
    type elt = a

    let elt_ty = Box.elt_ty

    module OPS = Box.OPS

    let boxed =
      if b then Box.OPS.add v Box.boxed else Box.OPS.remove v Box.boxed

    let size =
      let mem = Box.OPS.mem v Box.boxed in
      if mem then if b then Box.size else Box.size - 1
      else if b then Box.size + 1
      else Box.size
  end)

let mem : type elt. elt -> elt set -> bool =
 fun v (module Box) -> Box.OPS.mem v Box.boxed

let fold : type elt acc. (elt -> acc -> acc) -> elt set -> acc -> acc =
 fun f (module Box) -> Box.OPS.fold f Box.boxed

let size : type elt. elt set -> Script_int.n Script_int.num =
 fun (module Box) -> Script_int.(abs (of_int Box.size))
