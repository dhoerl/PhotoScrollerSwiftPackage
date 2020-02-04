# PhotoScrollerSwiftPackage
Extract PhotoScrollerNetwork into a Swift Package

Feb 1, 2020 : Working on this almost full time. Focused on a test app that will drive it.
  The data API will have two options: InputStream, or Combine Publisher (which uses the stream).
  These are now in the test application located in this project. The File based interface is done, 
  next is to add unit tests for the Web options (a day or two).
  
  Next step will be to complete the Swift Package and integrate it into the text app.
  
  Very happy how it progressing, but its taking a lot more time than the original code took (I did most 
  of that in a weekend, believe it or not, but I was a lot younger then too!)

Feb 3, 2020: Web based tests done and all passing - even hundreds of them. This 
  took an amazing amount of time and effort to get right. Networking on different threads
  is never easy.

Feb 4, 2020: The image decoding section is now coded, and at least passed the first unit test!
 The image contruction interface is an NSOutputStream - coded it to accept a delegate but it 
 really looks like that may not be needed, since it will consume as much data as you throw at it.
