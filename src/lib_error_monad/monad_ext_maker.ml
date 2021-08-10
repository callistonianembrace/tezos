(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2020 Nomadic Labs <contact@nomadic-labs.com>                *)
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

module Make (Error : sig
  type error = ..

  include Sig.CORE with type error := error

  include Sig.EXT with type error := error
end)
(Trace : Sig.TRACE)
(Monad : Tezos_lwt_result_stdlib.Lwtreslib.TRACED_MONAD
           with type 'error trace := 'error Trace.trace) :
  Sig.MONAD_EXT
    with type error := Error.error
     and type 'error trace := 'error Trace.trace = struct
  open Monad

  let fail e = Lwt.return_error (Trace.make e)

  let error e = Error (Trace.make e)

  type tztrace = Error.error Trace.trace

  type 'a tzresult = ('a, tztrace) result

  let trace_encoding = Trace.encoding Error.error_encoding

  let result_encoding a_encoding =
    let open Data_encoding in
    let trace_encoding = obj1 (req "error" trace_encoding) in
    let a_encoding = obj1 (req "result" a_encoding) in
    union
      ~tag_size:`Uint8
      [
        case
          (Tag 0)
          a_encoding
          ~title:"Ok"
          (function Ok x -> Some x | _ -> None)
          (function res -> Ok res);
        case
          (Tag 1)
          trace_encoding
          ~title:"Error"
          (function Error x -> Some x | _ -> None)
          (function x -> Error x);
      ]

  let pp_print_error = Trace.pp_print Error.pp

  let pp_print_error_first = Trace.pp_print_top Error.pp

  let classify_errors trace =
    Trace.fold
      (fun c e -> Sig.combine_category c (Error.classify_error e))
      `Temporary
      trace

  let record_trace err result =
    match result with
    | Ok _ as res -> res
    | Error trace -> Error (Trace.cons err trace)

  let trace err f =
    f >>= function
    | Error trace -> Lwt.return_error (Trace.cons err trace)
    | ok -> Lwt.return ok

  let record_trace_eval mk_err = function
    | Error trace -> mk_err () >>? fun err -> Error (Trace.cons err trace)
    | ok -> ok

  let trace_eval mk_err f =
    f >>= function
    | Error trace ->
        mk_err () >>=? fun err -> Lwt.return_error (Trace.cons err trace)
    | ok -> Lwt.return ok

  let error_unless cond exn = if cond then ok_unit else error exn

  let error_when cond exn = if cond then error exn else ok_unit

  let fail_unless cond exn = if cond then return_unit else fail exn

  let fail_when cond exn = if cond then fail exn else return_unit

  let unless cond f = if cond then return_unit else f ()

  let when_ cond f = if cond then f () else return_unit

  let dont_wait f err_handler exc_handler =
    Lwt.dont_wait
      (fun () ->
        f () >>= function
        | Ok () -> Lwt.return_unit
        | Error trace ->
            err_handler trace ;
            Lwt.return_unit)
      exc_handler
end
