(** Additional helpers for using generator. *)

(** Converts a string into a generator yielding individual characters. *)
let of_string s =
  let n = ref 0 in
  let n_max = String.length s in
  fun () ->
  if !n < n_max
  then
    let c = String.get s !n in
    let _ = incr n in
    Some c
  else
    None

(** Constructs a generator yielding successive lines from an input
    channel until it encounters an error.
 *)
let of_in_channel_lines chan =
  fun () ->
  try
    Some (input_line chan)
  with
  | _ -> None

(** Constructs a generator yielding successive characters from an
    input channel.
    Channel reads are internally buffered according to the optional
    argument buffer_size, which defaults to one KiB.
 *)
let of_in_channel ?(buffer_size = 1024) chan =
  let bs = Bytes.create buffer_size in
  let count = ref 0 in
  let i = ref 0 in
  let more () = count := input chan bs 0 buffer_size; i := 0 in
  let next () =
    let c = Bytes.get bs !i in
    incr i;
    Some c
  in
  more ();
  fun () ->
  match () with
  | _ when !count = 0 -> None
  | _ when i < count -> next ()
  | _ when i = count ->
     more ();
     if !count = 0 then
       None
     else
       next ()
  | () -> failwith "impossible"

(** Drops the first `ln` elements from the generator `g`. *)
let drop_lines g ln : unit =
  let rec go n =
    if n <= 0
    then ()
    else
      begin
        ignore (g ());
        go (n - 1)
      end
  in
  go ln

(** Transform a character generator into a line generator.
    This function assumes unix line endings, so it is not portable.

    This function also imposes a maximum line length specified via the
    `buffer_size` optional argument. (So that it uses constant memory.)
 *)
let line_generator ?(buffer_size = 2048) (g : char Gen.t) : string Gen.t =
  let bs = Bytes.create buffer_size in
  let finished = ref false in
  function
  | _ when !finished -> None
  | _ ->
     let got_nl = ref false in
     let i = ref 0 in
     while not !got_nl do
       let c = g () in
       match c with
       | None ->
          got_nl := true;
          finished := true
       | Some c ->
          Bytes.set bs !i c;
          incr i;
          got_nl := c = '\n'
     done;
     Some (Bytes.sub_string bs 0 !i)

(** Sequence a list of generators into one generator.
    Of course, if any generator in the sequence is infinite,
    subsequence generators will never be pulled from.
 *)
let sequence (gs : 'a Gen.t list) : 'a Gen.t =
  let rgs = ref gs in
  let rec go () =
    match !rgs with
    | [] -> None
    | g :: gs ->
       match g () with
       | None -> rgs := gs; go ()
       | e -> e
  in
  go

(** Construct a generator that will execute f on each element before yielding it. *)
let iter_through (f : 'a -> unit) (g : 'a Gen.t) : 'a Gen.t =
  let go () =
    let open Maybe in
    Gen.next g $> fun x -> f x; x
  in
  go