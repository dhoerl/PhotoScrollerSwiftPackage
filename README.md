# PhotoScrollerSwiftPackage
Extract PhotoScrollerNetwork into a Swift Package

Feb 1, 2020 : Working on this almost full time. Focused on a test app that will drive it.
  The data API will have two options: InputStream, or Combine Publisher (which uses the stream).
  These are now in the test application located in this project. The File based interface is done, 
  next is to add unit tests for the Web options (a day or two).
  
  Next step will be to complete the Swift Package and integrate it into the text app.
  
  Very happy how it progressing, but its taking a lot more time than the original code took (I did most 
  of that in a weekend, believe it or not, but I was a lot younger then too!)



1) Add the Package using Xcode->File->Packages with the URL of https://github.com/dhoerl/PhotoScrollerSwiftPackage

2) Open the Build Phases, and in the Package shown in the left file pane, drag the Libraries/libturbojpeg.a file into the link
   section. It will appear just above the PhotoScrollerSwiftPackage that should already be there

3) In Build settings, under library search paths, add:
   "$(BUILD_DIR)/../../SourcePackages/checkouts/PhotoScrollerSwiftPackage/Libraries"

