# PhotoScrollerSwiftPackage
Extract PhotoScrollerNetwork into a Swift Package

Version 0.4.0: this Swift Package is now usable. For usage look at the related PhotoScrollerNetworkTest
  project. Essentially TiledImageBuilder now offers a NSOutputStream interface, so you open it,
  feed it data chunks with write, then close it. The demo project shows how you can use local files
  as well as ones on the web.

Usage:

1) Add the Package using Xcode->File->Packages with the URL of https://github.com/dhoerl/PhotoScrollerSwiftPackage.

2) Open the Build Phases, and in the Package shown in the left file pane, drag the Libraries/libturbojpeg.a file into the link
   section. It will appear just above the PhotoScrollerSwiftPackage that should already be there

3) In Build settings, under library search paths, add:
   "$(BUILD_DIR)/../../SourcePackages/checkouts/PhotoScrollerSwiftPackage/Libraries"

NOTE: If you want to clone the Package and play with the code, then use a different library search path,
 for me this would be /Volumes/Data/git/PhotoScrollerSwiftPackage/Libraries.


Feb 11, 2020: Amazingly it's all working. Unit tests in the PhotoScrollerNetworkTest too!
 Really, if I'd known how much work this would be I probably wouldn't have done it. Virtually
 all the libturbojpeg interface code didn't change a bit. I had to update the Atomics to use stdAtomic,
 which took some time and effort. Then the code that manages memory consumption caused hangs:  in
 the end it was due to integer truncation - the size of modern memory overflowed integers.

Feb 4, 2020: The image decoding section is now coded, and at least passed the first unit test!
 The image contruction interface is an NSOutputStream - coded it to accept a delegate but it 
 really looks like that may not be needed, since it will consume as much data as you throw at it.

Feb 3, 2020: Web based tests done and all passing - even hundreds of them. This 
  took an amazing amount of time and effort to get right. Networking on different threads
  is never easy.

Feb 1, 2020 : Working on this almost full time. Focused on a test app that will drive it.
  The data API will have two options: InputStream, or Combine Publisher (which uses the stream).
  These are now in the test application located in this project. The File based interface is done, 
  next is to add unit tests for the Web options (a day or two).
  
  Next step will be to complete the Swift Package and integrate it into the text app.
  
  Very happy how it progressing, but its taking a lot more time than the original code took (I did most 
  of that in a weekend, believe it or not, but I was a lot younger then too!)

----

Apple's PhotoScroller project lets you display huge images using CATiledLayer, but only if
you pretile them first! My PhotoNetworkScroller project supports tiling large local
files and network fetches.

This package:

- blazingly fast tile rendering - visually much much faster than Apple's code (which uses png files in the file system)
- you supply a single jpeg file or URL and this code does all the tiling for you, quickly and painlessly
- builds on Apple's PhotoScroller project by addressing its deficiencies (mostly the pretiled images)
- provides the means to process very large images for use in a zoomable scrollview
- is backed by a CATiledLayer so that only those tiles needed for display consume memory
- each zoom level has one dedicated temp file rearranged into tiles for rapid tile access & rendering
