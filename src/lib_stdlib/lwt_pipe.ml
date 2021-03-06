(*****************************************************************************)
(*                                                                           *)
(* Open Source License                                                       *)
(* Copyright (c) 2018 Dynamic Ledger Solutions, Inc. <contact@tezos.com>     *)
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

open Lwt.Infix

type 'a t = {
  queue : (int * 'a) Queue.t;
  mutable current_size : int;
  max_size : int;
  compute_size : 'a -> int;
  mutable closed : bool;
  mutable push_waiter : (unit Lwt.t * unit Lwt.u) option;
  mutable pop_waiter : (unit Lwt.t * unit Lwt.u) option;
  empty : unit Lwt_condition.t;
}

let is_closed {closed; _} = closed

let push_overhead = 4 * (Sys.word_size / 8)

let create ?size () =
  let (max_size, compute_size) =
    match size with
    | None -> (max_int, fun _ -> 0)
    | Some (max_size, compute_size) -> (max_size, compute_size)
  in
  {
    queue = Queue.create ();
    current_size = 0;
    max_size;
    compute_size;
    closed = false;
    push_waiter = None;
    pop_waiter = None;
    empty = Lwt_condition.create ();
  }

let notify_push q =
  match q.push_waiter with
  | None -> ()
  | Some (_, w) ->
      q.push_waiter <- None ;
      Lwt.wakeup_later w ()

let notify_pop q =
  match q.pop_waiter with
  | None -> ()
  | Some (_, w) ->
      q.pop_waiter <- None ;
      Lwt.wakeup_later w ()

let wait_push q =
  match q.push_waiter with
  | Some (t, _) -> Lwt.protected t
  | None ->
      let (waiter, wakener) = Lwt.wait () in
      q.push_waiter <- Some (waiter, wakener) ;
      Lwt.protected waiter

let wait_pop q =
  match q.pop_waiter with
  | Some (t, _) -> Lwt.protected t
  | None ->
      let (waiter, wakener) = Lwt.wait () in
      q.pop_waiter <- Some (waiter, wakener) ;
      Lwt.protected waiter

let length {queue; _} = Queue.length queue

let is_empty {queue; _} = Queue.is_empty queue

let rec empty q =
  if is_empty q then Lwt.return_unit
  else Lwt_condition.wait q.empty >>= fun () -> empty q

exception Closed

let rec push ({closed; queue; current_size; max_size; compute_size; _} as q) elt
    =
  let elt_size = compute_size elt in
  if closed then Lwt.fail Closed
  else if current_size + elt_size < max_size || Queue.is_empty queue then (
    Queue.push (elt_size, elt) queue ;
    q.current_size <- current_size + elt_size ;
    notify_push q ;
    Lwt.return_unit)
  else wait_pop q >>= fun () -> push q elt

let push_now ({closed; queue; compute_size; current_size; max_size; _} as q) elt
    =
  if closed then raise Closed ;
  let elt_size = compute_size elt in
  (current_size + elt_size < max_size || Queue.is_empty queue)
  &&
  (Queue.push (elt_size, elt) queue ;
   q.current_size <- current_size + elt_size ;
   notify_push q ;
   true)

let rec pop ({closed; queue; empty; current_size; _} as q) =
  if not (Queue.is_empty queue) then (
    let (elt_size, elt) = Queue.pop queue in
    notify_pop q ;
    q.current_size <- current_size - elt_size ;
    if Queue.length queue = 0 then Lwt_condition.signal empty () ;
    Lwt.return elt)
  else if closed then Lwt.fail Closed
  else wait_push q >>= fun () -> pop q

let rec pop_with_timeout timeout q =
  if not (Queue.is_empty q.queue) then (
    Lwt.cancel timeout ;
    pop q >>= Lwt.return_some)
  else if Lwt.is_sleeping timeout then
    if q.closed then (
      Lwt.cancel timeout ;
      Lwt.fail Closed)
    else
      let waiter = wait_push q in
      Lwt.pick [timeout; Lwt.protected waiter] >>= fun () ->
      pop_with_timeout timeout q
  else Lwt.return_none

let rec peek ({closed; queue; _} as q) =
  if not (Queue.is_empty queue) then
    let (_elt_size, elt) = Queue.peek queue in
    Lwt.return elt
  else if closed then Lwt.fail Closed
  else wait_push q >>= fun () -> peek q

let peek_all {queue; closed; _} =
  if closed then []
  else List.rev (Queue.fold (fun acc (_, e) -> e :: acc) [] queue)

let pop_now ({closed; queue; empty; current_size; _} as q) =
  (* We only check for closed-ness when the queue is empty to allow reading from
     a closed pipe. This is because closing is just closing the write-end of the
     pipe. *)
  if Queue.is_empty queue && closed then raise Closed ;
  Queue.take_opt queue
  |> Stdlib.Option.map (fun (elt_size, elt) ->
         if Queue.length queue = 0 then Lwt_condition.signal empty () ;
         q.current_size <- current_size - elt_size ;
         notify_pop q ;
         elt)

let rec pop_all_loop q acc =
  match pop_now q with
  | None -> List.rev acc
  | Some e -> pop_all_loop q (e :: acc)

let pop_all q = pop q >>= fun e -> Lwt.return (pop_all_loop q [e])

let pop_all_now q = pop_all_loop q []

let close q =
  if not q.closed then (
    q.closed <- true ;
    notify_push q ;
    notify_pop q)
