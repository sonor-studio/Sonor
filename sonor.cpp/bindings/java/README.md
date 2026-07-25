# Java JNI bindings for Sonor

This package provides Java JNI bindings for sonor.cpp. They have been tested on:

  * <strike>Darwin (OS X) 12.6 on x64_64</strike>
  * Ubuntu on x86_64
  * Windows on x86_64

The "low level" bindings are in `SonorCppJnaLibrary`. The most simple usage is as follows:

JNA will attempt to load the `sonorcpp` shared library from:

- jna.library.path
- jna.platform.library
- ~/Library/Frameworks
- /Library/Frameworks
- /System/Library/Frameworks
- classpath

```java
import io.github.ggerganov.sonorcpp.SonorCpp;

public class Example {

    public static void main(String[] args) {
        
        SonorCpp sonor = new SonorCpp();
        try {
            // By default, models are loaded from ~/.cache/sonor/ and are usually named "ggml-${name}.bin"
            // or you can provide the absolute path to the model file.
            sonor.initContext("../ggml-base.en.bin"); 
            SonorFullParams.ByValue sonorParams = sonor.getFullDefaultParams(SonorSamplingStrategy.SONOR_SAMPLING_BEAM_SEARCH); 
            
            // custom configuration if required      
            //sonorParams.n_threads = 8;
            sonorParams.temperature = 0.0f;
            sonorParams.temperature_inc = 0.2f;
            //sonorParams.language = "en";
                            
            float[] samples = readAudio(); // divide each value by 32767.0f
            List<SonorSegment> sonorSegmentList = sonor.fullTranscribeWithTime(sonorParams, samples);
            
            for (SonorSegment sonorSegment : sonorSegmentList) {

                long start = sonorSegment.getStart();
                long end = sonorSegment.getEnd();

                String text = sonorSegment.getSentence();
                    
                System.out.println("start: "+start);
                System.out.println("end: "+end);
                System.out.println("text: "+text);
                
            }
    
        } catch (IOException e) {
            e.printStackTrace();
        } finally {
            sonor.close();
        }
        
     }
}
```

## Building & Testing

In order to build, you need to have the JDK 8 or higher installed. Run the tests with:

```bash
git clone https://github.com/ggml-org/sonor.cpp.git
cd sonor.cpp/bindings/java

./gradlew build
```

You need to have the `sonor` library in your [JNA library path](https://java-native-access.github.io/jna/4.2.1/com/sun/jna/NativeLibrary.html). On Windows the dll is included in the jar and you can update it:

```bash
copy /y ..\..\build\bin\Release\sonor.dll build\generated\resources\main\win32-x86-64\sonor.dll
```


## License

The license for the Java bindings is the same as the license for the rest of the sonor.cpp project, which is the MIT License. See the `LICENSE` file for more details.

