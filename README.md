# Chainloop Example Plugin

An example plugin for Chainloop that uses the experimental CLI plugin API. 

## Prerequisites

Keep in mind that this uses the experimental CLI plugin API, which is subject to change and is
not yet part of the Chainloop main branch. You need to check out the code from the 
[2090](https://github.com/chainloop-dev/chainloop/pull/2091) pull request branch and:

```bash
go mod edit -replace github.com/chainloop-dev/chainloop=../../chainloop/
```

The above command should reflect your directory structure. After that run:

```bash 
go mod tidy 
```

Before you'll be able to complie the code.

## Compiling 

```bash
go build -o plugin ./cmd/
```

## Installing (on macOS)

```bash
mv plugin "$HOME/Library/Application Support/chainloop/plugins/"
```
