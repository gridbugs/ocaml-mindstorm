(* OASIS_START *)
(* DO NOT EDIT (digest: 9852805d5c19ca1cb6abefde2dcea323) *)
(******************************************************************************)
(* OASIS: architecture for building OCaml libraries and applications          *)
(*                                                                            *)
(* Copyright (C) 2011-2013, Sylvain Le Gall                                   *)
(* Copyright (C) 2008-2011, OCamlCore SARL                                    *)
(*                                                                            *)
(* This library is free software; you can redistribute it and/or modify it    *)
(* under the terms of the GNU Lesser General Public License as published by   *)
(* the Free Software Foundation; either version 2.1 of the License, or (at    *)
(* your option) any later version, with the OCaml static compilation          *)
(* exception.                                                                 *)
(*                                                                            *)
(* This library is distributed in the hope that it will be useful, but        *)
(* WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY *)
(* or FITNESS FOR A PARTICULAR PURPOSE. See the file COPYING for more         *)
(* details.                                                                   *)
(*                                                                            *)
(* You should have received a copy of the GNU Lesser General Public License   *)
(* along with this library; if not, write to the Free Software Foundation,    *)
(* Inc., 51 Franklin St, Fifth Floor, Boston, MA  02110-1301 USA              *)
(******************************************************************************)

let () =
  try
    Topdirs.dir_directory (Sys.getenv "OCAML_TOPLEVEL_PATH")
  with Not_found -> ()
;;
#use "topfind";;
#require "oasis.dynrun";;
open OASISDynRun;;

(* OASIS_STOP *)

open OASISTypes

(* Naive libusb location detection *)
let usb_include =
  if Sys.file_exists "/usr/include/libusb-1.0/libusb.h" then
    "/usr/include/libusb-1.0/"
  else ""

let _ = BaseEnv.var_define "usb_include" (fun () -> usb_include)

(* Cannot use the value of the flag lwt because it has not been
   evaluated yet.  Directly check whether the library exists. *)
let has_lwt =
  try ignore(BaseCheck.package_version "lwt"); true
  with Failure _ -> false

let setup_t =
  if has_lwt then
    let add_deps = function
      | Flag(cs, flag) when cs.cs_name = "lwt" ->
         (* Automatically turn on the flag.  This is convenient for
            people compiling using "ocaml setup.ml -build". *)
         let flag = { flag with
                      flag_default = [(OASISExpr.EBool true, true)] } in
         Flag(cs, flag)
      | section -> section in
    let package =
      { setup_t.BaseSetup.package with
        sections = List.map add_deps setup_t.BaseSetup.package.sections } in
    { setup_t with BaseSetup.package = package }
  else
    setup_t

let () =
  BaseSetup.setup setup_t

