FROM ocaml/opam:debian-12-ocaml-5.0@sha256:855851458d189e362323ecb3294de1c79d704a9446d98fd89542536140a59105 AS build
RUN sudo apt-get update && sudo apt-get install libev-dev capnproto m4 pkg-config libsqlite3-dev libgmp-dev graphviz -y --no-install-recommends
RUN cd ~/opam-repository && git fetch -q origin master && git reset --hard e10b6ec1ad58b6faa39283ba79fe31b19b2a1897 && opam update
COPY --chown=opam multicoretests-ci.opam multicoretests-ci-lib.opam /src/
WORKDIR /src
RUN opam-2.1 install -y --deps-only .
ADD --chown=opam . .
RUN opam-2.1 exec -- dune build ./_build/install/default/bin/multicoretests-ci

FROM debian:12
RUN apt-get update && apt-get install libev4 openssh-client curl gnupg2 dumb-init git graphviz libsqlite3-dev ca-certificates netbase -y --no-install-recommends
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN echo 'deb https://download.docker.com/linux/debian buster stable' >> /etc/apt/sources.list
RUN apt-get update && apt-get install docker-ce docker-buildx-plugin -y --no-install-recommends
WORKDIR /var/lib/ocurrent
COPY --from=build /src/_build/install/default/bin/multicoretests-ci /usr/local/bin/
ENTRYPOINT ["dumb-init", "/usr/local/bin/multicoretests-ci"]
