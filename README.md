# EdhIm - Đ (Edh) doing Instant Messaging

This is a project demonstrating a few sweet spots found balanced between
_declarative_ and _imperative_ stylish, when put together, can make
[**Đ (Edh)**](https://github.com/e-wrks/edh)
code even more concise than **Haskell** code.

This repository can be used as the scaffold to start your **Haskell** +
**Edh** software development, as well as to run the demo yourself.

## Quick Start

```shell
curl -L https://github.com/e-wrks/edhim/archive/master.tar.gz | tar xzf -
mv edhim-master my-awsome-project
cd my-awsome-project
```

### Favouring [Cabal](https://www.haskell.org/cabal)

```shell
cabal v2-run edhim:edhim
```

### Favouring [Stack](https://haskellstack.org)

```shell
stack run
```

## TLDR

The usecase is the same as the
[Chat Example](https://github.com/simonmar/par-tutorial/blob/master/code/chat/Main.hs)
in Simon Marlow's classic book
[Parallel and Concurrent Programming with Haskell](https://simonmar.github.io/pages/pcph.html)

**EdhIm** talks through
[WebScokets](https://developer.mozilla.org/en-US/docs/Web/API/WebSockets_API)
so you use a web browser instead of
[cli](https://en.wikipedia.org/wiki/Command-line_interface)
to do chatting.

### Full Đ Code

https://github.com/e-wrks/edhim/blob/d12c409af0c3f8e5fc5bce61a9968d6c51dbe852/edh_modules/chat.edh#L2-L95

### World modeling code in Haskell

https://github.com/e-wrks/edhim/blob/d12c409af0c3f8e5fc5bce61a9968d6c51dbe852/edhim/src/ChatWorld.hs#L22-L210
