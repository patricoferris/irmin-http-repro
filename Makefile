all:
			dune build client/index.bc.js
			dune build server/main.exe
			dune exec -- server/main.exe

doc:
			dune runtest -p irmin-repro --auto-promote