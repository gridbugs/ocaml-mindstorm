(* File: mindstorm_NXT.ml

   Copyright (C) 2007-

     Christophe Troestler <Christophe.Troestler@umons.ac.be>
     WWW: http://math.umons.ac.be/anum/software/

   This library is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License version 2.1 or
   later as published by the Free Software Foundation, with the special
   exception on linking described in the file LICENSE.

   This library is distributed in the hope that it will be useful, but
   WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the file
   LICENSE for more details. *)


(* Implementation based on the "Bluetooth Developer Kit" available at
   http://mindstorms.lego.com/Overview/NXTreme.aspx

   See also:

   http://www.nabble.com/Bluetooth-Direct-and-System-Commands-t2288117.html
   http://mynxt.matthiaspaulscholz.eu/tools/index.html
   http://news.lugnet.com/robotics/nxt/nxthacking/?n=14
*)

(* TODO:
   - optional timeouts (for reading and receiving status)?
*)

#ifndef MODULE_ERR
(* Macros to use the correct module name in errors. *)
#define MODULE_ERR(err) STRINGIFY(Mindstorm.NXT: err)
#define MODULE(fn) STRINGIFY(Mindstorm.NXT.fn)
#endif

(* Monadic bindings and their imperative counterparts. *)
#ifdef LWT
open Lwt
#define ONLY_LWT(e) e
#define LET(v, expr) (expr) >>= fun v ->
#define EXEC(expr) (expr) >>= fun () ->
#define RETURN(x) Lwt.return(x)
#define FAIL(exn) Lwt.fail(exn)
#define UNIX(fn) Lwt_unix.fn
#define TRY_BIND(expr0, v, expr_v, exn_patt) \
  Lwt.try_bind (fun () -> expr0) (fun v -> expr_v) (function exn_patt)
#define EXCEPTION(e) e

#else
#define ONLY_LWT(e)
#define LET(v, expr) let v = expr in
#define EXEC(expr) (expr);
#define RETURN(x) (x)
#define FAIL(exn) raise(exn)
#define UNIX(fn) Unix.fn

#if OCAML_MAJOR >= 4 && OCAML_MINOR >= 2
(* More efficient *)
#define TRY_BIND(expr0, v, expr_v, exn_patt) \
  (match expr0 with v -> (expr_v) | exn_patt)
#define EXCEPTION(e) exception e

#else
type 'a val_or_exn = Val of 'a | Exn of exn
#define TRY_BIND(expr0, v, expr_v, exn_patt) \
  (match (try Val(expr0) with exn_ -> Exn exn_) with \
   | Val v -> (expr_v) \
   | Exn exn_ -> (match exn_ with exn_patt))
#define EXCEPTION(e) e
#endif

#endif

#include "mindstorm_common.ml"

type error ONLY_LWT(= Mindstorm_NXT.error) =
  | No_more_handles
  | No_space
  | No_more_files
  | EOF_expected
      (*     | End_of_file *) (* use the std exception *)
  | Not_a_linear_file
(*   | File_not_found *) (* separated *)
(*   | Handle_already_closed *)  (* SHOULD NOT HAPPEN *)
  | No_linear_space
  | Undefined_error
  | File_is_busy
  | No_write_buffers
  | Append_not_possible
  | File_is_full
  | File_exists
  | Module_not_found
  | Out_of_boundary
  | Illegal_file_name
(*  | Illegal_handle*)    (* SHOULD NOT HAPPEN *)

  (** command_error *)
  | Pending (** Pending communication transaction in progress *)
  | Empty_mailbox (** Specified mailbox queue is empty *)
  | Failed (** Request failed (i.e. specified file not found) *)
  | Unknown (** Unknown command opcode *)
  | Insane (** Insane packet *)
  | Out_of_range (** Data contains out-of-range values *)
  | Bus_error (** Communication bus error.  *)
  | Buffer_full (** No free memory in communication buffer *)
  | Invalid_conn (** Specified channel/connection is not valid *)
  | Busy_conn (** Specified channel/connection not configured or busy *)
  | No_program (** No active program *)
  | Bad_size (** Illegal size specified *)
  | Bad_mailbox (** Illegal mailbox queue ID specified *)
  | Bad_field (** Attempted to access invalid field of a structure *)
  | Bad_io (** Bad input or output specified *)
  | Out_of_memory (** Insufficient memory available *)
  | Bad_arg (** Bad arguments *)

#ifdef LWT
exception Error = Mindstorm_NXT.Error
exception File_not_found = Mindstorm_NXT.File_not_found
#else
exception Error of error
exception File_not_found
#endif

let success_char = '\x00'
let eof_char = '\x85'

let error =
  let e = Array.make 256 (Failure MODULE_ERR(undocumented error)) in
  (* Communication protocol errors *)
  e.(0x81) <- Error No_more_handles;
  e.(0x82) <- Error No_space;
  e.(0x83) <- Error No_more_files;
  e.(0x84) <- Error EOF_expected;
  e.(0x85) <- End_of_file (* Error EOF *);
  e.(0x86) <- Error Not_a_linear_file;
  e.(0x87) <- File_not_found;
  e.(0x88) <- Failure("Error Handle_already_closed");
  e.(0x89) <- Error No_linear_space;
  e.(0x8A) <- Error Undefined_error;
  e.(0x8B) <- Error File_is_busy;
  e.(0x8C) <- Error No_write_buffers;
  e.(0x8D) <- Error Append_not_possible;
  e.(0x8E) <- Error File_is_full;
  e.(0x8F) <- Error File_exists;
  e.(0x90) <- Error Module_not_found;
  e.(0x91) <- Error Out_of_boundary;
  e.(0x92) <- Error Illegal_file_name;
  e.(0x93) <- Failure("Error Illegal_handle");
  (* Direct commands errors *)
  e.(0x20) <- Error Pending;
  e.(0x40) <- Error Empty_mailbox;
  e.(0xBD) <- Error Failed;
  e.(0xBE) <- Error Unknown;
  e.(0xBF) <- Error Insane;
  e.(0xC0) <- Error Out_of_range;
  e.(0xDD) <- Error Bus_error;
  e.(0xDE) <- Error Buffer_full;
  e.(0xDF) <- Error Invalid_conn;
  e.(0xE0) <- Error Busy_conn;
  e.(0xEC) <- Error No_program;
  e.(0xED) <- Error Bad_size;
  e.(0xEE) <- Error Bad_mailbox;
  e.(0xEF) <- Error Bad_field;
  e.(0xF0) <- Error Bad_io;
  e.(0xFB) <- Error Out_of_memory;
  e.(0xFF) <- Error Bad_arg;
  e

let check_status_as_exn status =
  if status <> success_char then FAIL(error.(Char.code status))
  else RETURN()

(* ---------------------------------------------------------------------- *)
(** Connection *)

type usb
type bluetooth = UNIX(file_descr)

(* The type parameter is because we want to distinguish usb and
   bluetooth connections as some commands are only available through USB. *)
#ifdef LWT
type 'a conn_send = 'a -> Bytes.t -> unit Lwt.t
type 'a conn_recv = 'a -> int -> Bytes.t Lwt.t
type 'a conn_really_input = 'a -> Bytes.t -> int -> int -> unit Lwt.t
type 'a conn_close = 'a -> unit Lwt.t
#else
type 'a conn_send = 'a -> Bytes.t -> unit
type 'a conn_recv = 'a -> int -> Bytes.t
type 'a conn_really_input = 'a -> Bytes.t -> int -> int -> unit
type 'a conn_close = 'a -> unit
#endif
type 'a conn = {
  fd : 'a;
  (* We need specialized function depending on the fact that the
     connection is USB or bluetooth because bluetooth requires a
     prefix of 2 bytes indicating the length of the packet. *)
  send : 'a conn_send;
  (* [send fd pkg] sends the package [pkg] over [fd].  [pkg] is
     supposed to come prefixed with 2 bytes indicating its length
     (since this is necessary for bluetooth) -- they will be stripped
     for USB. *)
  recv : 'a conn_recv;
  (* [recv fd n] reads a package a length [n] and return it as a
     string.  For bluetooth, the prefix of 2 bytes indicating the
     length are also read but not returned (and not counted in [n]).
     [recv] checks the status byte and raise an exception accordingly
     (if needed). *)
  really_input : 'a conn_really_input;
  (* [really_input fd buf ofs len] reads [len] characters from [fd]
     and puts thrm in [buf] starting at position [ofs].  Do NOT read
     the bluetooth prefix bytes, so should not be used for packages
     but only for additional data. *)
  close : 'a conn_close;
  (* Close the connection. *)
  check_status : bool;
  (* Default value of the [check_status] optional arg. *)
}

let close conn = conn.close conn.fd

let recv conn n =
  LET(pkg, conn.recv conn.fd n)
  EXEC(check_status_as_exn (Bytes.get pkg 2))
  RETURN(pkg)

let default_check_status conn = function
  | None -> conn.check_status
  | Some s -> s


(** USB -------------------- *)
module USB =
struct
  type device (* a handle to a USB LEGO device. *)

#ifdef HAS_USB
#ifdef MACOSX
  (* Mac OS X *)
  let bricks () = RETURN([])
  let connect ?(check_status=false) socket =
    FAIL(Failure "Not yet implemented")
    (* libusb should work *)

#elif defined WIN32 || defined WIN64 || defined CYGWIN
  (* Windows *)
  let bricks () = RETURN([])
  let connect ?(check_status=false) socket =
    FAIL(Failure "Not yet implemented")
    (* See http://www.microsoft.com/whdc/connect/usb/winusb_howto.mspx *)

#else
  (* Unix *)
  external bricks : unit -> device list = "ocaml_mindstorm_bricks"
  external exit_libusb : unit -> unit = "ocaml_mindstorm_exit"
  external connect_device : device -> usb = "ocaml_mindstorm_connect_usb"
  external close : usb -> unit = "ocaml_mindstorm_close_usb"
  external write : usb -> string -> int -> int -> unit
    = "ocaml_mindstorm_usb_write"
  external really_input : usb -> string -> int -> int -> unit
    = "ocaml_mindstorm_usb_really_input"

  let () = at_exit exit_libusb

#ifdef LWT
  (* Is there a better solution? *)
  let bricks = Lwt_preemptive.detach bricks
  let connect_device = Lwt_preemptive.detach connect_device
  let close = Lwt_preemptive.detach close
  let write usb s ofs len =
    Lwt_preemptive.detach (write usb s ofs) len
  let really_input usb s ofs len =
    Lwt_preemptive.detach (really_input usb s ofs) len
#endif

  let recv usb n =
    let buf = Bytes.create n in
    EXEC(really_input usb buf 0 n)
    RETURN(buf)

  (* Ignore the first 2 bytes of [pkg] that are for bluetooth only *)
  let send fd pkg = write fd pkg 2 (Bytes.length pkg - 2)

  let connect ?(check_status=false) dev =
    LET(fd, connect_device dev)
    RETURN({ fd = fd;  send = send;
             recv = recv;  really_input = really_input;
             close = close;
             check_status = check_status })

#endif
#else
  (* No USB libary *)
  let bricks () = RETURN([])
  let connect ?(check_status=false) socket =
    FAIL(Failure "The Mindstorm module was compiled without USB support")
#endif
end

(** Bluetooth -------------------- *)

let bt_send fd pkg =
  LET(_, UNIX(write) fd pkg 0 (Bytes.length pkg))
  RETURN()

let bt_recv fd n =
  LET(_size, really_read fd 2)
  LET(pkg, really_read fd n)
  assert(Bytes.get pkg 0 = '\x02');
  (* pkg.[1] is the cmd id, do we check it ?? *)
  (* We wanted to check the status and raise the corresponding
     exception here but we cannot because of the behavior of [input]. *)
  RETURN(pkg)


#ifdef MACOSX
(* Mac OS X *)
let connect_bluetooth ?(check_status=false) tty =
  LET(fd, UNIX(openfile) tty [Unix.O_RDWR] 0o660)
  RETURN({ fd = fd;  send = bt_send;
           recv = bt_recv;  really_input = really_input_fd;
           close = UNIX(close);
           check_status = check_status })

#elif defined WIN32 || defined WIN64 || defined CYGWIN
(* Windows *)
external socket_bluetooth : string -> Unix.file_descr
  = "ocaml_mindstorm_connect"

#ifdef LWT
let socket_bluetooth s =
  Lwt_preemptive.detach socket_bluetooth s >>= fun fd ->
  Lwt.return(Lwt_unix.of_unix_file_descr fd)
#endif

let connect_bluetooth ?(check_status=false) addr =
  LET(fd, socket_bluetooth ("\\\\.\\" ^ addr))
  RETURN({ fd = fd;  send = bt_send;
           recv = bt_recv;  really_input = really_input_fd;
           close = Unix.close;
           check_status = check_status })

#else
(* Unix *)
external socket_bluetooth : string -> Unix.file_descr
  = "ocaml_mindstorm_connect"

#ifdef LWT
let socket_bluetooth s =
  Lwt_preemptive.detach socket_bluetooth s >>= fun fd ->
  Lwt.return(Lwt_unix.of_unix_file_descr fd)
#endif

let connect_bluetooth ?(check_status=false) addr =
  LET(fd, socket_bluetooth addr)
  RETURN({ fd = fd;  send = bt_send;
           recv = bt_recv;  really_input = really_input_fd;
           close = UNIX(close);
           check_status = check_status })

#endif


(* ---------------------------------------------------------------------- *)
(** System commands *)

type 'a in_channel = {
  in_fd : 'a;
  in_send : 'a conn_send;
  in_recv : 'a conn_recv;
  in_really_input : 'a conn_really_input;
  in_handle : char; (* the handle given by the brick *)
  in_length : int; (* file size *)
  mutable in_left : int; (* number of bytes left to be read,
                            = 0 iff EOF
                            < 0 iff the channel is closed *)
}

let open_in conn fname =
  let pkg = Bytes.create 24 in
  Bytes.set pkg 0 '\022'; (* size, LSB *)
  Bytes.set pkg 1 '\000'; (* size, MSB *)
  Bytes.set pkg 2 '\x01';
  Bytes.set pkg 3 '\x80'; (* OPEN READ *)
  blit_filename MODULE(open_in) fname pkg 4;
  EXEC(conn.send conn.fd pkg)
  LET(ans, recv conn 8)
  let len = uint32 ans 4 in (* len <= 64Kb of RAM *)
  RETURN({ in_fd = conn.fd;
           in_send = conn.send;
           in_recv = conn.recv;
           in_really_input = conn.really_input;
           in_handle = Bytes.get ans 3;
           in_length = len;
           in_left = len;
         })

let in_channel_length ch =
  if ch.in_left < 0 then FAIL(Sys_error "Closed NXT in_channel")
  else RETURN(ch.in_length)

let close_in ch =
  if ch.in_left >= 0 then begin
    (* Channel not yet closed. *)
    let pkg = Bytes.create 5 in
    Bytes.set pkg 0 '\003'; (* size, LSB *)
    Bytes.set pkg 1 '\000'; (* size, MSB *)
    Bytes.set pkg 2 '\x01';
    Bytes.set pkg 3 '\x84'; (* CLOSE *)
    Bytes.set pkg 4 ch.in_handle;
    EXEC(ch.in_send ch.in_fd pkg)
    LET(ans, ch.in_recv ch.in_fd 4)
    ch.in_left <- -1;
    check_status_as_exn (Bytes.get ans 2)
  end
  else RETURN()

let input ch buf ofs len =
  if ofs < 0 || len < 0 || ofs + len > Bytes.length buf || len > 0xFFFF then
    FAIL(Invalid_argument (MODULE(input)))
  else if ch.in_left < 0 then FAIL(Sys_error MODULE_ERR(Closed NXT in_channel))
  else if ch.in_left = 0 then FAIL(End_of_file)
  else if len = 0 then RETURN(0)
  else begin
    let len_to_read = min len ch.in_left (* > 0 *) in
    let pkg = Bytes.create 7 in
    Bytes.set pkg 0 '\005'; (* size, LSB *)
    Bytes.set pkg 1 '\000'; (* size, MSB *)
    Bytes.set pkg 2 '\x01';
    Bytes.set pkg 3 '\x82'; (* READ *)
    Bytes.set pkg 4 ch.in_handle;
    copy_uint16 len_to_read pkg 5;
    EXEC(ch.in_send ch.in_fd pkg)
    (* Variable length return package.  The number of bytes that was
       requested [len_to_read] is always returned.  Beware that if we
       read the last bytes -- even if there were indeed bytes to read --
       the status will indicate EOF. *)
    LET(ans, ch.in_recv ch.in_fd 6)
    let r = uint16 ans 4 in (* # bytes read *)
    assert(r = len_to_read);
    EXEC(ch.in_really_input ch.in_fd buf ofs len_to_read)
    ch.in_left <- ch.in_left - len_to_read;
    let status = Bytes.get ans 2 in
    (* We manage EOF ourselves to respect OCaml conventions: *)
    if status = success_char || status = eof_char then RETURN(len_to_read)
    else (EXEC(check_status_as_exn status) RETURN(0))
  end

type 'a out_channel = {
  out_fd : 'a;
  out_send : 'a conn_send;
  out_recv : 'a conn_recv;
  out_handle : char; (* the handle given by the brick *)
  out_length : int; (* size provided by the user of the brick *)
  mutable out_closed : bool;
}

type out_flag =
    [ `File of int
    | `Linear of int
    | `Data of int
    | `Append
    ]

(* FIXME: On 64 bits, one must check [length < 2^32] => AMD64 macro*)
let open_out_gen conn flag_byte length fname =
  if length < 0 then FAIL(Invalid_argument MODULE(open_out))
  else (
    let pkg = Bytes.create 28 in
    Bytes.set pkg 0 '\026'; (* size, LSB *)
    Bytes.set pkg 1 '\000'; (* size, MSB *)
    Bytes.set pkg 2 '\x01';
    Bytes.set pkg 3 flag_byte; (* type of open *)
    blit_filename MODULE(open_out) fname pkg 4;
    copy_uint32 length pkg 24; (* length <= 64Kb of RAM *)
    EXEC(conn.send conn.fd pkg)
    LET(ans, recv conn 4)
    RETURN({ out_fd = conn.fd;
             out_send = conn.send;
             out_recv = conn.recv;
             out_handle = Bytes.get ans 3;
             out_length = length;
             out_closed = false;
    })
  )

let open_out_append conn fname =
  let pkg = Bytes.create 24 in
  Bytes.set pkg 0 '\022'; (* size, LSB *)
  Bytes.set pkg 1 '\000'; (* size, MSB *)
  Bytes.set pkg 2 '\x01';
  Bytes.set pkg 3 '\x8C'; (* OPEN APPEND DATA *)
  blit_filename MODULE(open_out) fname pkg 4;
  EXEC(conn.send conn.fd pkg)
  LET(ans, recv conn 8)
  RETURN({ out_fd = conn.fd;
           out_send = conn.send;
           out_recv = conn.recv;
           out_handle = Bytes.get ans 3;
           out_length = uint32 ans 4; (* <= 64Kb of RAM *)
           out_closed = false;
         })

let open_out conn (flag: out_flag) fname =
  match flag with
  | `File len -> open_out_gen conn '\x81' len fname (* OPEN WRITE *)
  | `Linear len -> open_out_gen conn '\x89' len fname (* OPEN WRITE LINEAR *)
  | `Data len -> open_out_gen conn '\x8B' len fname (* OPEN WRITE DATA *)
  | `Append -> open_out_append conn fname

let out_channel_length ch =
  if ch.out_closed then raise(Sys_error "Closed NXT out_channel");
  ch.out_length

let close_out ch =
  if not ch.out_closed then begin
    let pkg = Bytes.create 5 in
    Bytes.set pkg 0 '\003'; (* size, LSB *)
    Bytes.set pkg 1 '\000'; (* size, MSB *)
    Bytes.set pkg 2 '\x01';
    Bytes.set pkg 3 '\x84'; (* CLOSE *)
    Bytes.set pkg 4 ch.out_handle;
    EXEC(ch.out_send ch.out_fd pkg)
    LET(ans, ch.out_recv ch.out_fd 4)
    ch.out_closed <- true; (* let the channel be closed even in case of error *)
    check_status_as_exn (Bytes.get ans 2)
  end
  else RETURN()

let output ch buf ofs len =
  if ofs < 0 || len < 0 || ofs + len > String.length buf || len > 0xFFFC then
    FAIL(Invalid_argument MODULE(output))
  else if ch.out_closed then FAIL(Sys_error "Closed NXT out_channel")
  else (
    let pkg = Bytes.create (5 + len) in
    copy_uint16 (len + 3) pkg 0; (* 2 BT length bytes; len+3 <= 0xFFFF *)
    Bytes.set pkg 2 '\x01';
    Bytes.set pkg 3 '\x83'; (* WRITE *)
    Bytes.set pkg 4 ch.out_handle;
    String.blit buf ofs pkg 5 len;
    EXEC(ch.out_send ch.out_fd pkg)
    LET(ans, ch.out_recv ch.out_fd 6)
    EXEC(check_status_as_exn (Bytes.get ans 2))
    RETURN(uint16 ans 4)
  )

let remove conn fname =
  let pkg = Bytes.create 24 in
  Bytes.set pkg 0 '\022'; (* size, LSB *)
  Bytes.set pkg 1 '\000'; (* size, MSB *)
  Bytes.set pkg 2 '\x01';
  Bytes.set pkg 3 '\x85'; (* DELETE *)
  blit_filename MODULE(remove) fname pkg 4;
  EXEC(conn.send conn.fd pkg)
  LET(_, recv conn 23) (* check status *)
  RETURN()

module Find =
struct
  type 'a iterator = {
    it_fd : 'a;
    it_send : 'a conn_send;
    it_recv : 'a conn_recv;
    it_handle : char;
    mutable it_closed : bool;
    mutable it_fname : string; (* current filename *)
    mutable it_flength : int; (* current filename length. *)
  }

  let close it =
    if not it.it_closed && it.it_flength >= 0 then begin
      (* The iterator is not closed and has requested a handle. *)
      let pkg = Bytes.create 5 in
      Bytes.set pkg 0 '\003'; (* size, LSB *)
      Bytes.set pkg 1 '\000'; (* size, MSB *)
      Bytes.set pkg 2 '\x01';
      Bytes.set pkg 3 '\x84'; (* CLOSE *)
      Bytes.set pkg 4 it.it_handle;
      EXEC(it.it_send it.it_fd pkg)
      LET(ans, it.it_recv it.it_fd 4)
      it.it_closed <- true; (* close even if an exception is raised *)
      check_status_as_exn (Bytes.get ans 2)
    end
    else RETURN()

  let patt conn fpatt =
    let pkg = Bytes.create 24 in
    Bytes.set pkg 0 '\022'; (* size, LSB *)
    Bytes.set pkg 1 '\000'; (* size, MSB *)
    Bytes.set pkg 2 '\x01';
    Bytes.set pkg 3 '\x86'; (* FIND FIRST *)
    blit_filename MODULE(find) fpatt pkg 4;
    EXEC(conn.send conn.fd pkg)
    LET(ans, recv conn 28) (* might raise File_not_found *)
    RETURN({ it_fd = conn.fd;
             it_send = conn.send;
             it_recv = conn.recv;
             it_handle = Bytes.get ans 3;
             it_closed = false;
             it_fname = get_filename ans 4;
             it_flength = uint32 ans 24; (* length <= 64Kb of RAM *)
           })

  let closed_exn = Sys_error MODULE_ERR(Closed NXT file_iterator)

  let current i =
    if i.it_closed then FAIL(closed_exn)
    else RETURN(i.it_fname)

  let current_size i =
    if i.it_closed then FAIL(closed_exn)
    else RETURN(i.it_flength)

  let next i =
    if i.it_closed then FAIL(closed_exn)
    else (
      let pkg = Bytes.create 5 in
      Bytes.set pkg 0 '\003'; (* size, LSB *)
      Bytes.set pkg 1 '\000'; (* size, MSB *)
      Bytes.set pkg 2 '\x01';
      Bytes.set pkg 3 '\x87'; (* FIND NEXT *)
      Bytes.set pkg 4 i.it_handle;
      EXEC(i.it_send i.it_fd pkg)
      LET(ans, i.it_recv i.it_fd 28)
      i.it_fname <- get_filename ans 4;
      i.it_flength <- uint32 ans 24; (* length <= 64Kb of RAM *)
      (* In the case the status is File_not_found, the doc says the
         handle is closed by the brick. (FIXME: confirm?) *)
      if Bytes.get ans 2 = eof_char then i.it_closed <- true;
      check_status_as_exn (Bytes.get ans 2)
    )

  let rec iter_loop f i =
    TRY_BIND(f i.it_fname i.it_flength,
             (), (TRY_BIND(next i,
                           (), iter_loop f i,
                           EXCEPTION(File_not_found) -> RETURN()
                         | EXCEPTION(e) -> EXEC(close i) FAIL(e)
                 )),
             EXCEPTION(e) ->
               EXEC(close i) (* exn raised by [f] must close the iterator *)
               FAIL(e))

  let iter conn ~f fpatt =
    TRY_BIND(patt conn fpatt,
             i, iter_loop f i,
             EXCEPTION(File_not_found) -> RETURN()
           | EXCEPTION(e) -> FAIL(e))

  let rec fold_loop f i a =
    TRY_BIND(f i.it_fname i.it_flength a,
             a, (TRY_BIND(next i,
                          (), fold_loop f i a,
                          EXCEPTION(File_not_found) -> RETURN(a)
                        | EXCEPTION(e) -> EXEC(close i) FAIL(e)
                )),
             EXCEPTION(e) ->
               EXEC(close i) (* exn raised by [f] must close the iterator *)
               FAIL(e))

  let fold conn ~f fpatt a0 =
    TRY_BIND(patt conn fpatt,
             i, fold_loop f i a0,
             EXCEPTION(File_not_found) -> RETURN(a0)
           | EXCEPTION(e) -> FAIL(e))

  let map conn ~f patt =
    let l = ref [] in
    EXEC(iter conn patt ~f:(fun name length ->
             LET(v, f name length)
             RETURN(l := v :: !l)))
    RETURN(List.rev !l)
end

(* ---------------------------------------------------------------------- *)
(** Brick info *)

let firmware_version_pkg = Bytes.of_string "\002\000\x01\x88"
let firmware_version conn =
  EXEC(conn.send conn.fd firmware_version_pkg)
  LET(ans, recv conn 7)
  RETURN((Char.code(Bytes.get ans 4), Char.code(Bytes.get ans 3),
          Char.code(Bytes.get ans 6), Char.code(Bytes.get ans 5)))

let boot conn =
  let arg = "Let's dance: SAMBA" in
  let len = String.length arg in
  let pkg = Bytes.create 23 in
  Bytes.set pkg 0 '\021';
  Bytes.set pkg 1 '\000';
  Bytes.set pkg 2 '\x01';
  Bytes.set pkg 3 '\x97'; (* BOOT COMMAND *)
  String.blit arg 0 pkg 4 len;
  Bytes.fill pkg (4 + len) (19 - len) '\000';
  EXEC(conn.send conn.fd pkg)
  LET(_, recv conn 7)
  RETURN()

let rec check_brick_name name i len =
  if i < len then
    if name.[i] < ' ' || name.[i] >= '\127' then
      FAIL(Invalid_argument
             (MODULE(set_brick_name: name contains invalid chars)))
    else check_brick_name name (i + 1) len
  else RETURN()

let set_brick_name ?check_status conn name =
  let check_status = default_check_status conn check_status in
  let len = String.length name in
  if len > 15 then
    FAIL(Invalid_argument MODULE(set_brick_name: name too long (max 15 chars)))
  else (
    EXEC(check_brick_name name 0 (String.length name))
    let pkg = Bytes.create 20 in
    Bytes.set pkg 0 '\018'; (* size, LSB *)
    Bytes.set pkg 1 '\000'; (* size, MSB *)
    Bytes.set pkg 2 (if check_status then '\x01' else '\x81');
    Bytes.set pkg 3 '\x98'; (* SET BRICK NAME *)
    String.blit name 0 pkg 4 len;
    Bytes.fill pkg (4 + len) (16 - len) '\000'; (* pad if needed *)
    EXEC(conn.send conn.fd pkg)
    if check_status then (LET(_, recv conn 3) RETURN())
    else RETURN()
  )

type brick_info ONLY_LWT(= Mindstorm_NXT.brick_info) = {
  brick_name : string;
  bluetooth_addr : string;
  signal_strength : int;
  free_user_flash : int;
}

let get_brick_name s i0 i1 =
  (** Extract the brick name of "" if it fails (should not happen). *)
  try
    let j = min i1 (Bytes.index_from s i0 '\000') in
    Bytes.sub_string s i0 (j - i0)
  with Not_found -> ""

let string_of_bluetooth_addr =
  let u s i = Char.code(String.unsafe_get s i) in
  fun addr ->
    assert(String.length addr = 6);
    Printf.sprintf "%02x:%02x:%02x:%02x:%02x:%02x"
      (u addr 0) (u addr 1) (u addr 2) (u addr 3) (u addr 4) (u addr 5)

let device_info_pkg = Bytes.of_string "\002\000\x01\x9B"
let get_device_info conn =
  EXEC(conn.send conn.fd device_info_pkg) (* GET DEVICE INFO *)
  LET(ans, recv conn 33)
  RETURN({ brick_name = get_brick_name ans 3 17; (* 14 chars + null *)
           bluetooth_addr = (* ans.[18 .. 24], drop null terminator *)
             string_of_bluetooth_addr(Bytes.sub_string ans 18 6);
           signal_strength = uint32 ans 25; (* always return 0! *)
           free_user_flash = uint32 ans 29; (* <= 64Kb of RAM *)
         })

let delete_user_flash_pkg = Bytes.of_string "\002\000\x01\xA0"
let delete_user_flash conn =
  EXEC(conn.send conn.fd delete_user_flash_pkg) (* DELETE USER FLASH *)
  LET(_, recv conn 3)
  RETURN()

let bluetooth_reset_pkg = Bytes.of_string "\002\000\x01\xA4"
let bluetooth_reset conn =
  EXEC(conn.send conn.fd bluetooth_reset_pkg) (* BLUETOOTH FACTORY RESET *)
  LET(_, recv conn 3)
  RETURN()

let char_of_buffer_type = function
  | `Poll_buffer -> '\x00'
  | `High_speed_buffer -> '\x01'

let poll_length conn buf =
 let pkg = Bytes.create 5 in
  Bytes.set pkg 0 '\003'; (* 2 bluetooth bytes *)
  Bytes.set pkg 1 '\000';
  Bytes.set pkg 2 '\x01';
  Bytes.set pkg 3 '\xA1'; (* POLL COMMAND LENGTH *)
  Bytes.set pkg 4 (char_of_buffer_type buf);
  EXEC(conn.send conn.fd pkg)
  LET(ans, recv conn 5)
  RETURN(Char.code(Bytes.get ans 4))

let poll_command conn buf len =
 let pkg = Bytes.create 6 in
  Bytes.set pkg 0 '\004'; (* 2 bluetooth bytes *)
  Bytes.set pkg 1 '\000';
  Bytes.set pkg 2 '\x01';
  Bytes.set pkg 3 '\xA2'; (* POLL COMMAND *)
  Bytes.set pkg 4 (char_of_buffer_type buf);
  Bytes.set pkg 5 (char_of_int len);
  EXEC(conn.send conn.fd pkg)
  LET(ans, recv conn 65)
  RETURN((Char.code(Bytes.get ans 4),
          Bytes.sub_string ans 5 60)) (* FIXME: Null terminator? *)


let keep_alive_pkg = Bytes.of_string "\002\000\x00\x0D"
let keep_alive conn =
  EXEC(conn.send conn.fd keep_alive_pkg) (* KEEPALIVE *)
  LET(ans, recv conn 7)
  RETURN(uint32 ans 3) (* FIXME: # of miliseconds can overflow 30 bits? *)


let battery_level_pkg = Bytes.of_string "\002\000\x00\x0B"
let battery_level conn =
  EXEC(conn.send conn.fd battery_level_pkg) (* GETBATTERYLEVEL *)
  LET(ans, recv conn 5)
  RETURN(uint16 ans 3)


(* ---------------------------------------------------------------------- *)
(** Direct commands *)

(* More documentation about the system commands is provided in the
   "Executable File and Bytecode Reference" downloadable from
   http://mindstorms.lego.com/Overview/NXTreme.aspx.  *)

(* Generic function to send a command of [n] bytes without an answer
   (but with the option of checking the return status).  [fill] is
   responsible for filling [pkg] according to the command.  BEWARE
   that because of the 2 BT bytes, all indexes must be shifted by +2
   w.r.t. the spec. *)
let cmd conn ~check_status ~byte1 ~n fill =
  assert(n <= 0xFF); (* all fixed length commands *)
  let pkg = Bytes.create (n + 2) in
  Bytes.set pkg 0 (Char.unsafe_chr n); (* size, LSB *)
  Bytes.set pkg 1 '\000'; (* size, MSB *)
  Bytes.set pkg 2 (if check_status then '\x00' else '\x80');
  Bytes.set pkg 3 byte1;
  fill pkg;
  EXEC(conn.send conn.fd pkg)
  if check_status then (LET(_, recv conn 3) RETURN())
  else RETURN()

module Program =
struct
  let start ?check_status conn name =
    let check_status = default_check_status conn check_status in
    cmd conn ~check_status ~byte1:'\x00' ~n:22  begin fun pkg ->
      blit_filename MODULE(Program.start) name pkg 4
    end

  let stop ?check_status conn =
    let check_status = default_check_status conn check_status in
    cmd conn ~check_status ~byte1:'\x01' ~n:2 (fun _ -> ())

  let name_pkg = Bytes.of_string "\002\000\x00\x11"
  let name conn =
    EXEC(conn.send conn.fd name_pkg) (* GETCURRENTPROGRAMNAME *)
    LET(ans, recv conn 23)
    RETURN(get_filename ans 3)
end


module Motor =
struct
  type port = char
  let a = '\x00'
  let b = '\x01'
  let c = '\x02'
  let all = '\xFF'

  type regulation = [ `Idle | `Motor_speed | `Motor_sync ]
      (* It is a bit strange one does not seem to be allowed to specify
         [`Motor_speed] and [`Motor_sync] at the same time... but the
         "NXT Executable File Specification" says clearly "Unlike the
         MODE property, REG_MODE is not a bitfield. You can set only
         one REG_MODE value at a time." *)
  type run_state = [ `Idle | `Ramp_up | `Running | `Ramp_down ]


  type state ONLY_LWT(= Mindstorm_NXT.Motor.state) = {
    speed : int;
    motor_on : bool; (* FIXME: do we remove this and set
                        motor_on = (speed <> 0) ? *)
    brake : bool;
    regulation : regulation;
    turn_ratio : int;
    run_state : run_state;
    tach_limit : int;
  }

  let speed ?(tach_limit=0) ?(brake=true) ?(sync=false) ?(turn_ratio=0) s =
    {
      speed = s;   motor_on = s <> 0;  brake = brake;
      regulation = (if sync then `Motor_sync else `Motor_speed);
      turn_ratio = turn_ratio;
      run_state = `Running;
      tach_limit = tach_limit; (* 0 -> run forever *)
    }



  let set ?check_status conn port st =
    let check_status = default_check_status conn check_status in
    if st.tach_limit < 0 then
      FAIL(Invalid_argument MODULE(Motor.set: state.tach_limit must be >= 0))
    else (
      (* SETOUTPUTSTATE *)
      cmd conn ~check_status ~byte1:'\x04' ~n:13   begin fun pkg ->
        Bytes.set pkg 4 port;
        Bytes.set pkg 5 (signed_chr st.speed);
        let mode = 0x00 (* COAST mode *) in
        let mode = if st.motor_on then mode lor 0x01 else mode in
        let mode = if st.brake then mode lor 0x02 else mode in
        (* [Regulate]: Enables active power regulation according to
           value of REG_MODE (interactive motors only).  You must use
           the REGULATED bit in conjunction with the REG_MODE property =>
           [regulate] influences 2 bytes send to the brick *)
        let mode, regulation = (match st.regulation with
                                | `Idle -> mode, '\x00'
                                | `Motor_speed -> mode lor 0x04, '\x01'
                                | `Motor_sync  -> mode lor 0x04, '\x02') in
        Bytes.set pkg 6 (Char.unsafe_chr mode);
        Bytes.set pkg 7 regulation;
        Bytes.set pkg 8 (signed_chr st.turn_ratio);
        Bytes.set pkg 9 (match st.run_state with
                         | `Idle -> '\x00' | `Ramp_up -> '\x10'
                         | `Running -> '\x20' | `Ramp_down -> '\x40');
        copy_uint32 st.tach_limit pkg 10; (* bytes 8-11 (bug in the spec) *)
      end
    )

  let get conn motor =
    let pkg = Bytes.create 5 in
    Bytes.set pkg 0 '\003'; (* BT bytes *)
    Bytes.set pkg 1 '\000';
    Bytes.set pkg 2 '\x00'; (* get an answer *)
    Bytes.set pkg 3 '\x06'; (* GETOUTPUTSTATE *)
    Bytes.set pkg 4 motor;
    EXEC(conn.send conn.fd pkg)
    LET(ans, recv conn 25)
    let mode = Char.code(Bytes.get ans 5) in
    let st =
      { speed = signed_code (Bytes.get ans 4);
        motor_on = (mode land 0x01 <> 0);
        brake = (mode land 0x02 <> 0);
        regulation = (if mode land 0x04 = 0 then `Idle
                      else match Bytes.get ans 6 with
                      | '\x00' -> `Idle
                      | '\x01' -> `Motor_speed
                      | '\x02' -> `Motor_sync
                      | _ -> `Idle);
        turn_ratio = signed_code (Bytes.get ans 7);
        run_state = (match Bytes.get ans 8 with
                     | '\x00' -> `Idle | '\x10' -> `Ramp_up
                     | '\x20' -> `Running | '\x40' -> `Ramp_down
                     | _ -> `Idle);
        tach_limit = uint32 ans 9;
      }
    and tach_count = int32 ans 13
    and block_tach_count = int32 ans 17
    and rotation_count = int32 ans 21
      (* The Exec. File Spec. says ROTATION_COUNT Legal value range is
         [-2147483648, 2147483647] so all 32 bits may be used. *) in
    RETURN((st, tach_count, block_tach_count, rotation_count))


  let reset_pos ?check_status conn ?(relative=false) port =
    let check_status = default_check_status conn check_status in
    (* RESETMOTORPOSITION *)
    cmd conn ~check_status ~byte1:'\x0A' ~n:4 (fun pkg ->
      Bytes.set pkg 4 port;
      Bytes.set pkg 5 (if relative then '\x01' else '\x00');
    )
end


module Sensor =
struct
  type t
  type port = [ `S1 | `S2 | `S3 | `S4 ]
  type sensor_type =
      [ `No_sensor
      | `Switch
      | `Temperature
      | `Reflection
      | `Angle
      | `Light_active
      | `Light_inactive
      | `Sound_db
      | `Sound_dba
      | `Custom
      | `Lowspeed
      | `Lowspeed_9v
      | `Highspeed
      | `Color_full
      | `Color_red
      | `Color_green
      | `Color_blue
      | `Color_none
      ]
  type mode =
      [ `Raw
      | `Bool
      | `Transition_cnt
      | `Period_counter
      | `Pct_full_scale
      | `Celsius
      | `Fahrenheit
      | `Angle_steps
      | `Slope_mask
      (*| `Mode_mask*)
      ]


  let char_of_port = function
    | `S1 -> '\000' | `S2 -> '\001'
    | `S3 -> '\002' | `S4 -> '\003'

  let set ?check_status conn port sensor_type sensor_mode =
    let check_status = default_check_status conn check_status in
    cmd conn ~check_status ~byte1:'\x05' ~n:5 begin fun pkg ->
      Bytes.set pkg 4 (char_of_port port);
      Bytes.set pkg 5 (match sensor_type with
                       | `No_sensor      -> '\x00'
                       | `Switch         -> '\x01'
                       | `Temperature -> '\x02'
                       | `Reflection     -> '\x03'
                       | `Angle  -> '\x04'
                       | `Light_active -> '\x05'
                       | `Light_inactive -> '\x06'
                       | `Sound_db       -> '\x07'
                       | `Sound_dba      -> '\x08'
                       | `Custom         -> '\x09'
                       | `Lowspeed       -> '\x0A'
                       | `Lowspeed_9v -> '\x0B'
                       | `Highspeed      -> '\x0C'
                       (* From the Lejos "SensorsConstants.java": *)
                       | `Color_full   -> '\x0D'
                       | `Color_red    -> '\x0E'
                       | `Color_green  -> '\x0F'
                       | `Color_blue   -> '\x10'
                       | `Color_none   -> '\x11');
      Bytes.set pkg 6 (match sensor_mode with
                       | `Raw    -> '\x00'
                       | `Bool   -> '\x20'
                       | `Transition_cnt -> '\x40'
                       | `Period_counter -> '\x60'
                       | `Pct_full_scale -> '\x80'
                       | `Celsius        -> '\xA0'
                       | `Fahrenheit     -> '\xC0'
                       | `Angle_steps -> '\xE0'
                       | `Slope_mask     -> '\x1F'
                       | `Mode_mask      -> '\xE0' (* = `Angle_steps !! *)
                      );
    end

  type data ONLY_LWT(= Mindstorm_NXT.Sensor.data) = {
    sensor_type : sensor_type;
    mode : mode;
    valid : bool;
    (* is_calibrated : bool; *)
    raw : int;
    normalized : int;
    scaled : int;
    (* calibrated: int *)
  }

  let get conn port =
    let pkg = Bytes.create 5 in
    Bytes.set pkg 0 '\003'; (* BT bytes *)
    Bytes.set pkg 1 '\000';
    Bytes.set pkg 2 '\x00'; (* get a reply *)
    Bytes.set pkg 3 '\x07'; (* GETINPUTVALUES *)
    Bytes.set pkg 4 (char_of_port port);
    EXEC(conn.send conn.fd pkg)
    LET(ans, recv conn 16)
    RETURN({ valid = Bytes.get ans 4 <> '\x00';
             sensor_type = (match Bytes.get ans 6 with
                            | '\x00' -> `No_sensor
                            | '\x01' -> `Switch
                            | '\x02' -> `Temperature
                            | '\x03' -> `Reflection
                            | '\x04' -> `Angle
                            | '\x05' -> `Light_active
                            | '\x06' -> `Light_inactive
                            | '\x07' -> `Sound_db
                            | '\x08' -> `Sound_dba
                            | '\x09' -> `Custom
                            | '\x0A' -> `Lowspeed
                            | '\x0B' -> `Lowspeed_9v
                            | '\x0C' -> `Highspeed
                            | '\x0D' -> `Color_full
                            | '\x0E' -> `Color_red
                            | '\x0F' -> `Color_green
                            | '\x10' -> `Color_blue
                            | '\x11' -> `Color_none
                            | _ -> raise(Error Out_of_range));
             mode = (match Bytes.get ans 7 with
                     | '\x00' -> `Raw
                     | '\x20' -> `Bool
                     | '\x40' -> `Transition_cnt
                     | '\x60' -> `Period_counter
                     | '\x80' -> `Pct_full_scale
                     | '\xA0' -> `Celsius
                     | '\xC0' -> `Fahrenheit
                     | '\xE0' -> `Angle_steps
                     | '\x1F' -> `Slope_mask
                     (*| '\xE0' -> `Mode_mask*)
                     | _ -> raise(Error Out_of_range));
             raw = uint16 ans 8;
             normalized = uint16 ans 10;
             scaled = int16 ans 12;
             (* calibrated = int16 and 14; *)
    })

  let color_of_scaled_tab =
    [| `Black (* unused *) ; `Black; `Blue; `Green; `Yellow; `Red; `White |]
  let color_of_data data =
    if data.sensor_type <> `Color_full then
      invalid_arg MODULE(Sensor.color_of_scaled: the sensor
                         type must be `Color_full);
    if data.scaled < 1 || data.scaled > 6 then
      invalid_arg MODULE(Sensor.color_of_scaled: scaled data
                         out of range);
    color_of_scaled_tab.(data.scaled)


  let reset_scaled ?check_status conn port =
    let check_status = default_check_status conn check_status in
    (* RESETINPUTSCALEDVALUE *)
    cmd conn ~check_status ~byte1:'\x08' ~n:3  begin fun pkg ->
      Bytes.set pkg 4 (char_of_port port)
    end

  (** {3 Low speed} *)

  let get_status conn port =
    let pkg = Bytes.create 5 in
    Bytes.set pkg 0 '\003'; (* 2 BT bytes *)
    Bytes.set pkg 1 '\000';
    Bytes.set pkg 2 '\x00';
    Bytes.set pkg 3 '\x0E'; (* LSGETSTATUS *)
    Bytes.set pkg 4 (char_of_port port);
    EXEC(conn.send conn.fd pkg)
    LET(ans, recv conn 4)
    RETURN(Char.code (Bytes.get ans 3))

  let write ?check_status conn port ?(rx_length=0) tx_data =
    let check_status = default_check_status conn check_status in
    let n = String.length tx_data in
    if n > 255 then
      FAIL(Invalid_argument MODULE(Sensor.write: length tx_data > 255))
    else if rx_length < 0 || rx_length > 255 then
      FAIL(Invalid_argument
             (MODULE(Sensor.write: length rx_length not in 0 .. 255)))
    else (
      let pkg = Bytes.create (7 + n) in
      copy_uint16 (n + 5) pkg 0; (* 2 bluetooth bytes *)
      Bytes.set pkg 2 (if check_status then '\x00' else '\x80');
      Bytes.set pkg 3 '\x0F'; (* LSWRITE *)
      Bytes.set pkg 4 (char_of_port port);
      Bytes.set pkg 5 (Char.unsafe_chr n); (* tx bytes (# bytes sent) *)
      Bytes.set pkg 6 (Char.unsafe_chr rx_length);
      String.blit tx_data 0 pkg 7 n;
      EXEC(conn.send conn.fd pkg)
      if check_status then (LET(_, recv conn 3) RETURN())
      else RETURN()
    )

  let read conn port =
    let pkg = Bytes.create 5 in
    Bytes.set pkg 0 '\003'; (* 2 bluetooth bytes *)
    Bytes.set pkg 1 '\000';
    Bytes.set pkg 2 '\x00';
    Bytes.set pkg 3 '\x10'; (* LSREAD *)
    Bytes.set pkg 4 (char_of_port port);
    EXEC(conn.send conn.fd pkg)
    LET(ans, recv conn 20)
    let rx_length = min (Char.code (Bytes.get ans 3)) 16 in
    RETURN(Bytes.sub_string ans 4 rx_length)

  (** Ultrasonic sensor *)
  (* Specification of the I2C protocol for the ultrasonic sensor given
     in the Appendix 7 of "Hardware Developer Kit" available at
     http://mindstorms.lego.com/Overview/NXTreme.aspx *)
  module Ultrasonic =
  struct
    type 'a t = {
      u_fd : 'a;
      u_send : 'a conn_send;
      u_recv : 'a conn_recv;
      port : char;
      ls_status : Bytes.t; (* share the string across all status calls *)
    }

    let make conn port =
      (* We need to let the I2C time to init, so better to check the
         return status. *)
      EXEC(set ~check_status:true conn port `Lowspeed_9v `Raw)
      let port = char_of_port port in
      let ls_status = Bytes.create 5 in
      Bytes.set ls_status 0 '\003'; (* 2 BT bytes *)
      Bytes.set ls_status 1 '\000';
      Bytes.set ls_status 2 '\x00';
      Bytes.set ls_status 3 '\x0E'; (* LSGETSTATUS *)
      Bytes.set ls_status 4 port;
      RETURN({ u_fd = conn.fd;
               u_send = conn.send;
               u_recv = conn.recv;
               port = port;
               ls_status = ls_status;
             })

    let write_cmd ~check_status us byte2 byte3 =
      (* Special write because the string length is statically known *)
      let pkg = Bytes.create 10 in
      Bytes.set pkg 0 '\008';  Bytes.set pkg 1 '\000'; (* 2 BT bytes *)
      Bytes.set pkg 2 (if check_status then '\x00' else '\x80');
      Bytes.set pkg 3 '\x0F'; (* LSWRITE *)
      Bytes.set pkg 4 us.port;
      Bytes.set pkg 5 '\003'; (* tx bytes (# bytes sent) *)
      Bytes.set pkg 6 '\000'; (* rx bytes (length answer) *)
      Bytes.set pkg 7 '\x02'; (* 1st byte of command: I2C dev *)
      Bytes.set pkg 8 byte2;  (* 2nd byte of command *)
      Bytes.set pkg 9 byte3;  (* 3rd byte of command *)
      EXEC(us.u_send us.u_fd pkg)
      if check_status then begin
          LET(ans, us.u_recv us.u_fd 3)
          check_status_as_exn (Bytes.get ans 2)
        end
      else RETURN()

    let write_val ~check_status us cmd byte2 v =
      if v < 0 || v > 255 then
        FAIL(Invalid_argument (Printf.sprintf MODULE(Sensor.Ultrasonic.set:
                                              %s arg not in 0 .. 255) cmd))
      else
        write_cmd ~check_status us byte2 (Char.unsafe_chr v)

    let set ?(check_status=true) us cmd =
      match cmd with
      | `Off ->       write_cmd ~check_status us '\x41' '\x00'
      | `Meas ->      write_cmd ~check_status us '\x41' '\x01'
      | `Meas_cont -> write_cmd ~check_status us '\x41' '\x02'
      | `Event ->     write_cmd ~check_status us '\x41' '\x03'
      | `Reset ->     write_cmd ~check_status us '\x41' '\x04'
      | `Meas_interval i -> write_val ~check_status us "`Meas_interval" '\x40' i
      | `Zero z -> write_val ~check_status us "`Zero" '\x50' z
      | `Scale_mul m -> write_val ~check_status us "`Scale_mul" '\x51' m
      | `Scale_div d -> write_val ~check_status us "`Scale_div" '\x52' d

    (* See [read] above *)
    let lsread us =
      let pkg = Bytes.create 5 in
      Bytes.set pkg 0 '\003'; (* 2 BT bytes *)
      Bytes.set pkg 1 '\000';
      Bytes.set pkg 2 '\x00';
      Bytes.set pkg 3 '\x10'; (* LSREAD *)
      Bytes.set pkg 4 us.port;
      EXEC(us.u_send us.u_fd pkg)
      LET(ans, us.u_recv us.u_fd 20)
      EXEC(check_status_as_exn (Bytes.get ans 2))
      RETURN(ans) (* I2C data starts at byte 4 *)

    let lswrite us addr =
      let pkg = Bytes.create 9 in
      Bytes.set pkg 0 '\007';  Bytes.set pkg 1 '\000'; (* 2 BT bytes *)
      Bytes.set pkg 2 '\x00'; (* Request answer *)
      Bytes.set pkg 3 '\x0F'; (* LSWRITE *)
      Bytes.set pkg 4 us.port;
      Bytes.set pkg 5 '\002'; (* tx bytes (2 bytes sent) *)
      Bytes.set pkg 6 '\001'; (* rx bytes (1 bytes to read) *)
      Bytes.set pkg 7 '\x02'; (* 1st byte of command: I2C dev *)
      Bytes.set pkg 8 addr;
      (* 'Restart Messaging + 0x03', is sent by the brick itself. *)
      EXEC(us.u_send us.u_fd pkg)
      LET(ans, us.u_recv us.u_fd 3)
      check_status_as_exn (Bytes.get ans 2)

    let data_ready us =
      EXEC(us.u_send us.u_fd us.ls_status)
      LET(ans, us.u_recv us.u_fd 4)
      EXEC(check_status_as_exn (Bytes.get ans 2))
      RETURN(Bytes.get ans 3 <> '\000')

    let get_state us =
      EXEC(lswrite us '\x41') (* Read command state *)
      LET(ans, lsread us)
      match Bytes.get ans 4 with
      | '\x00' -> RETURN(`Off)
      | '\x01' -> RETURN(`Meas)
      | '\x02' -> RETURN(`Meas_cont)
      | '\x03' -> RETURN(`Event)
      | '\x04' -> RETURN(`Reset)
      | _ -> FAIL(Failure(MODULE(Sensor.Ultrasonic.get_state)))

    let get us var =
      (* Retry any pending garbage bytes in the NXT buffers.  FIXME:
         when is this needed?  It can even stall the program if no
         bytes are to be read!  *)
      (* ignore(lsread us); *)
      (* Retrieve the data of [var] *)
      let v = match var with (* 2nd byte of command: var to read *)
        | `Byte0 -> '\x42'
        | `Byte1 -> '\x43'
        | `Byte2 -> '\x44'
        | `Byte3 -> '\x45'
        | `Byte4 -> '\x46'
        | `Byte5 -> '\x47'
        | `Byte6 -> '\x48'
        | `Byte7 -> '\x49'
        | `Meas_interval -> '\x40'
        | `Zero -> '\x50'
        | `Scale_mul -> '\x51'
        | `Scale_div -> '\x52' in
      EXEC(lswrite us v)
      (* Check the status of I2C message channel until idle, timeout or
         an error occurs. FIXME: until? needed? *)
(*    if not(data_ready us) then failwith MODULE(Sensor.Ultrasonic.get); *)
      (* Read sensor data *)
      LET(data, lsread us)
      RETURN(Char.code (Bytes.get data 4))

  end
end

module Sound =
struct
  let play ?check_status conn ?(loop=false) fname =
    let check_status = default_check_status conn check_status in
    cmd conn ~check_status ~byte1:'\x02' ~n:23 (fun pkg ->
      Bytes.set pkg 4 (if loop then '\x01' else '\x00');
      blit_filename MODULE(Sound.play) fname pkg 5
    )

  let stop ?check_status conn =
    let check_status = default_check_status conn check_status in
    cmd conn ~check_status ~byte1:'\x0C' ~n:2 (fun _ -> ())

  let play_tone ?check_status conn freq duration =
    let check_status = default_check_status conn check_status in
    if freq < 200 || freq > 14000 then
      FAIL(Invalid_argument
             (MODULE(Sound.play_tone: frequency not in 200 .. 14000)))
    else
      cmd conn ~check_status ~byte1:'\x03' ~n:6 (fun pkg ->
          copy_uint16 freq pkg 4;
          copy_uint16 duration pkg 6
        )
end

module Message =
struct
  type mailbox = [`B0 | `B1 | `B2 | `B3 | `B4 | `B5 | `B6 | `B7 | `B8 | `B9]
  type remote = [`R0 | `R1 | `R2 | `R3 | `R4 | `R5 | `R6 | `R7 | `R8 | `R9]

  let char_of_mailbox = function
    | `B0 -> '\000' | `B1 -> '\001' | `B2 -> '\002'
    | `B3 -> '\003' | `B4 -> '\004' | `B5 -> '\005'
    | `B6 -> '\006' | `B7 -> '\007' | `B8 -> '\008'
    | `B9 -> '\009'
    | `R0 -> '\010' | `R1 -> '\011' | `R2 -> '\012'
    | `R3 -> '\013' | `R4 -> '\014' | `R5 -> '\015'
    | `R6 -> '\016' | `R7 -> '\017' | `R8 -> '\018'
    | `R9 -> '\019'

  let write ?(check_status=true) conn mailbox msg =
    let len = String.length msg in
    if len > 58 then
      FAIL(Invalid_argument MODULE(Message.write: message length > 58))
    else (
      let pkg = Bytes.create (len + 7) in
      copy_uint16 (len + 5) pkg 0; (* cmd length = 4+msg length + one '\000' *)
      Bytes.set pkg 2 (if check_status then '\x00' else '\x80');
      Bytes.set pkg 3 '\x09';
      Bytes.set pkg 4 (char_of_mailbox mailbox);
      Bytes.set pkg 5 (Char.unsafe_chr len);
      String.blit msg 0 pkg 6 len;
      Bytes.set pkg (len+6) '\000';
      EXEC(conn.send conn.fd pkg)
      if check_status then (LET(_, recv conn 3) RETURN())
      else RETURN()
    )

  let read conn ?(remove=false) mailbox =
    let pkg = Bytes.create 7 in
    Bytes.set pkg 0 '\005'; (* 2 bluetooth bytes *)
    Bytes.set pkg 1 '\000';
    Bytes.set pkg 2 '\x00'; (* request answer *)
    Bytes.set pkg 3 '\x13'; (* MESSAGEREAD *)
    Bytes.set pkg 4 (char_of_mailbox mailbox); (* remote inbox *)
    Bytes.set pkg 5 '\000'; (* local inbox; unused.  FIXME: normal? *)
    Bytes.set pkg 6 (if remove then '\x01' else '\x00');
    EXEC(conn.send conn.fd pkg)
    LET(ans, recv conn 64)
    let len = try Bytes.index_from ans 5 '\000' - 5 with Not_found -> 59 in
    RETURN(Bytes.sub_string ans 5 len)
end
