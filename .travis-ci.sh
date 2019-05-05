# Edit this for your own project dependencies
OPAM_DEPENDS="ocamlfind extlib ulex"

export OPAMYES=1
export OPAMVERBOSE=1
echo OCaml version
ocaml -version
echo OPAM versions
opam --version
opam --git-version

opam init --comp=$OCAML_VERSION
eval `opam config env`
opam install ${OPAM_DEPENDS}
make all && ./TEST && (./TEST -- +htmltest) && (./TEST -- +sexp)
