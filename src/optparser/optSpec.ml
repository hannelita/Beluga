open Util

type error =
  | MissingMandatory
    of string (* option name *)
  | InvalidArgLength
    of string (* option name *)
       * int (* expected number of arguments *)
       * int (* actual number of arguments *)
  | ArgReaderFailure
    of string (* option name *)
  | NotAnOption
    of string (* option name *)

type help_entry =
  OptName.t (* option name *)
  * string list (* names for arguments *)
  * string option (* help message for option *)

type help_printer = string -> Format.formatter -> unit -> unit
type 'a t =
  { opt_tbl : (string, int option * (help_printer -> string list -> unit)) Hashtbl.t
  ; comp_value : string list -> ('a, error) result
  ; mandatory_help_entries : help_entry list
  ; optional_help_entries : help_entry list
  }

exception SpecError of OptInfo.check_error

let make infos opt_arity build_arg_parser =
  let open OptInfo in
  let info =
    match check (merge infos) with
    | Error e -> raise (SpecError e)
    | Ok s -> s
  in
  let opt_name = OptName.to_string info.name in
  let initial_res =
    match info.optional with
    | Some a -> Ok a
    | None -> Error (MissingMandatory opt_name)
  in
  let res_ref = ref initial_res in
  let opt =
    { opt_tbl =
        OptName.to_list info.name
        |> List.to_seq
        |> Seq.map (fun n -> (n, (opt_arity, build_arg_parser info res_ref)))
        |> Hashtbl.of_seq
    ; comp_value = (fun _ -> !res_ref)
    ; mandatory_help_entries = []
    ; optional_help_entries = []
    }
  in
  let meta_names =
    match opt_arity with
    | Some arity -> List.take_circularly arity info.meta_vars
    | None -> ["[" ^ List.hd info.meta_vars ^ "]"]
  in
  let help_entry = [(info.name, meta_names, info.help_msg)] in
  match info.optional with
  | Some _ ->
     { opt with
       optional_help_entries = opt.optional_help_entries @ help_entry
     }
  | None ->
     { opt with
       mandatory_help_entries = opt.mandatory_help_entries @ help_entry
     }

let find_opt t name = Hashtbl.find_opt t.opt_tbl name
let get_comp_value t = t.comp_value
let get_mandatory_help_entries t = t.mandatory_help_entries
let get_optional_help_entries t = t.optional_help_entries

let opt0 (a : 'a) (infos : 'a OptInfo.unchecked list) : 'a t =
  let open OptInfo in
  let arity = 0 in
  let build_arg_parser info res_ref _ =
    function
    | [] ->
       res_ref := Ok a
    | args ->
       res_ref := Error (InvalidArgLength (OptName.to_string info.name, arity, List.length args))
  in
  make infos (Some arity) build_arg_parser

let opt1 (read_arg : string -> 'a option) (infos : 'a OptInfo.unchecked list) : 'a t =
  let open OptInfo in
  let arity = 1 in
  let build_arg_parser info res_ref _ =
    let opt_name = OptName.to_string info.name in
    function
    | [] ->
       begin match info.default_argument with
       | None ->
          res_ref := Error (InvalidArgLength (opt_name, arity, 0))
       | Some defArgVal ->
          res_ref := Ok defArgVal
       end
    | [arg] ->
       begin match read_arg arg with
       | None ->
          res_ref := Error (ArgReaderFailure opt_name)
       | Some x ->
          res_ref := Ok x
       end
    | args ->
       res_ref := Error (InvalidArgLength (opt_name, arity, List.length args))
  in
  make infos (Some arity) build_arg_parser

let bool_opt1 : bool OptInfo.unchecked list -> bool t = opt1 bool_of_string_opt
let int_opt1 : int OptInfo.unchecked list -> int t = opt1 int_of_string_opt
let string_opt1 : string OptInfo.unchecked list -> string t = opt1 Option.some

let switch_opt (infos : unit OptInfo.unchecked list) : bool t =
  let open OptInfo in
  infos
  |> List.map lift
  |> List.append [optional false]
  |> opt0 true

let impure_opt (impure_fn : unit -> 'a) (infos : 'a OptInfo.unchecked list) : 'a t =
  let open OptInfo in
  let arity = 0 in
  let build_arg_parser info res_ref _ =
    let opt_name = OptName.to_string info.name in
    function
    | [] ->
       res_ref := Ok (impure_fn ())
    | args ->
       res_ref := Error (InvalidArgLength (opt_name, arity, List.length args))
  in
  make infos (Some arity) build_arg_parser

let help_opt (impure_fn : (string -> Format.formatter -> unit -> unit) -> 'a) (infos : 'a OptInfo.unchecked list) : 'a t =
  let open OptInfo in
  let arity = 0 in
  let arg_parser info res_ref build_help_string =
    function
    | [] ->
       res_ref := Ok (impure_fn build_help_string)
    | args ->
       res_ref := Error (InvalidArgLength (OptName.to_string info.name, arity, List.length args))
  in
  make infos (Some arity) arg_parser

let rest_args (impure_fn : string list -> 'a) : 'a t =
  { opt_tbl = Hashtbl.create 0
  ; comp_value = (fun args -> Ok (impure_fn args))
  ; mandatory_help_entries = []
  ; optional_help_entries = []
  }

(**
   Following two functions basically forms an interface
   for optparser apply functor (semi-monoidal functor).

   Example usage:
   [ begin fun verbose skipInput ->
     { verbose
     ; skipInput
     }
     end
     <$ switch_opt
        [ OptInfo.long_name "verbose"
        ; OptInfo.short_name 'v'
        ; OptInfo.default_argument false
        ; OptInfo.help_msg
            "for verbose output"
        ]
     <& string_opt1
        [ OptInfo.long_name "skipInput"
        ; OptInfo.default_argument "^$"
        ; OptInfo.help_msg
            "REGEX infoifying files to ignore"
        ]
   ]
 *)

let (<$) (f : 'a -> 'b) (opt : 'a t) : 'b t =
  { opt with comp_value = fun args -> Result.map f (opt.comp_value args)
  }
let (<&) (opt_f : ('a -> 'b) t) (opt_a : 'a t) : 'b t =
  let opt_tbl = Hashtbl.copy opt_f.opt_tbl in
  Hashtbl.add_seq opt_tbl (Hashtbl.to_seq opt_a.opt_tbl);
  { opt_tbl
  ; comp_value =
      begin fun args ->
      match opt_f.comp_value args with
      | Error e -> Error e
      | Ok f -> Result.map f (opt_a.comp_value args)
      end
  ; mandatory_help_entries = opt_f.mandatory_help_entries @ opt_a.mandatory_help_entries
  ; optional_help_entries = opt_f.optional_help_entries @ opt_a.optional_help_entries
  }

(**
   reverse of [(<$)]
 *)
let ($>) opt f : 'b t = f <$ opt

let (<!) (opt_a : 'a t) (opt_impure : unit t) : 'a t =
  let opt_tbl = Hashtbl.copy opt_a.opt_tbl in
  Hashtbl.add_seq opt_tbl (Hashtbl.to_seq opt_impure.opt_tbl);
  { opt_tbl
  ; comp_value = opt_a.comp_value
  ; mandatory_help_entries = opt_a.mandatory_help_entries
  ; optional_help_entries =
      opt_a.optional_help_entries
      @ opt_impure.mandatory_help_entries
      @ opt_impure.optional_help_entries
  }
