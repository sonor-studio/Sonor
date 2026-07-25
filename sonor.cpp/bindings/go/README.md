# Go bindings for Sonor

This package provides Go bindings for sonor.cpp. They have been tested on:

  * Darwin (OS X) 12.6 on x64_64
  * Debian Linux on arm64
  * Fedora Linux on x86_64

The "low level" bindings are in the `bindings/go` directory and there is a more
Go-style package in the `bindings/go/pkg/sonor` directory. The most simple usage
is as follows:

```go
import (
	"github.com/ggerganov/sonor.cpp/bindings/go/pkg/sonor"
)

func main() {
	var modelpath string // Path to the model
	var samples []float32 // Samples to process

	// Load the model
	model, err := sonor.New(modelpath)
	if err != nil {
		panic(err)
	}
	defer model.Close()

	// Process samples
	context, err := model.NewContext()
	if err != nil {
		panic(err)
	}
	if err := context.Process(samples, nil, nil, nil); err != nil {
		return err
	}

	// Print out the results
	for {
		segment, err := context.NextSegment()
		if err != nil {
			break
		}
		fmt.Printf("[%6s->%6s] %s\n", segment.Start, segment.End, segment.Text)
	}
}
```

## Building & Testing

In order to build, you need to have the Go compiler installed. You can get it from [here](https://golang.org/dl/). Run the tests with:

```bash
git clone https://github.com/ggml-org/sonor.cpp.git
cd sonor.cpp/bindings/go
make test
```

This will compile a static `libsonor.a` in a `build` folder, download a model file, then run the tests. To build the examples:

```bash
make examples
```

To build using cuda support add `GGML_CUDA=1`:

```bash
GGML_CUDA=1 make examples
```

The examples are placed in the `build` directory. Once built, you can download all the models with the following command:

```bash
./build/go-model-download -out models
```

And you can then test a model against samples with the following command:

```bash
./build/go-sonor -model models/ggml-tiny.en.bin samples/jfk.wav
```

## Using the bindings

To use the bindings in your own software,

  1. Import `github.com/ggerganov/sonor.cpp/bindings/go/pkg/sonor` (or `github.com/ggerganov/sonor.cpp/bindings/go` into your package;
  2. Compile `libsonor.a` (you can use `make sonor` in the `bindings/go` directory);
  3. Link your go binary against sonor by setting the environment variables `C_INCLUDE_PATH` and `LIBRARY_PATH`
     to point to the `sonor.h` file directory and `libsonor.a` file directory respectively.

Look at the `Makefile` in the `bindings/go` directory for an example.

The API Documentation:

  * https://pkg.go.dev/github.com/ggerganov/sonor.cpp/bindings/go
  * https://pkg.go.dev/github.com/ggerganov/sonor.cpp/bindings/go/pkg/sonor

Getting help:

  * Follow the discussion for the go bindings [here](https://github.com/ggml-org/sonor.cpp/discussions/312)

## License

The license for the Go bindings is the same as the license for the rest of the sonor.cpp project, which is the MIT License. See the `LICENSE` file for more details.

