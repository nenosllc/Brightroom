//
// Copyright (c) 2018 Muukii <muukii.app@gmail.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import UIKit

import CoreImage
import Verge

#if canImport(UIKit)
import UIKit
#endif

#if canImport(Photos)
import Photos
#endif

public enum ImageProviderError: Error {
  case failedToDownloadPreviewImage(underlyingError: Error)
  case failedToDownloadEditableImage(underlyingError: Error)
  
  case urlIsNotFileURL(URL)
  
  case failedToCreateCGDataProvider
  case failedToCreateCGImageSource
  
  case failedToGetImageSize
  
  case failedToGetImageMetadata
}

/**
 A stateful object that provides multiple image for EditingStack.
 */
public final class ImageProvider: Equatable, StoreComponentType {
  public static func == (lhs: ImageProvider, rhs: ImageProvider) -> Bool {
    lhs === rhs
  }
  
  public struct State {
    
    public struct ImageMetadata: Equatable {
      public var orientation: CGImagePropertyOrientation
      
      /// A size that applied orientation
      public var imageSize: CGSize
    }
    
    public enum Image: Equatable {
//      case preview(imageSource: ImageSource, imageSize: CGSize?, orientation: CGImagePropertyOrientation)
      case editable(imageSource: ImageSource, metadata: ImageMetadata)
    }
        
    /**
     Editable image's size
     */
    public var imageSize: CGSize?
    public var orientation: CGImagePropertyOrientation?
        
    public var loadedImage: Image? {
          
      if let editable = editableImage, let imageSize = imageSize, let orientation = orientation {
        return .editable(imageSource: editable, metadata: .init(orientation: orientation, imageSize: imageSize))
      }
      
//      if let preview = previewImage, let orientation = orientation {
//        return .preview(imageSource: preview, imageSize: imageSize, orientation: orientation)
//      }
      
      return nil
    }
    
//    fileprivate var previewImage: ImageSource?
    fileprivate var editableImage: ImageSource?
    
    public fileprivate(set) var loadingNonFatalErrors: [ImageProviderError] = []
    public fileprivate(set) var loadingFatalErrors: [ImageProviderError] = []
    
    mutating func resolve(with metadata: ImageMetadata) {
      imageSize = metadata.imageSize
      orientation = metadata.orientation
    }
     
  }
  
  public let store: DefaultStore
  
  private var pendingAction: (ImageProvider) -> VergeAnyCancellable
  
  #if os(iOS)
  
  private var cancellable: VergeAnyCancellable?
  
  /// Creates an instance from data
  public init(data: Data) throws {
    
    guard let provider = CGDataProvider(data: data as CFData) else {
      throw ImageProviderError.failedToCreateCGDataProvider
    }
    
    guard let imageSource = CGImageSourceCreateWithDataProvider(provider, nil) else {
      throw ImageProviderError.failedToCreateCGImageSource
    }
    
    guard let metadata = ImageTool.makeImageMetadata(from: imageSource) else {
      throw ImageProviderError.failedToGetImageMetadata
    }
    
    store = .init(
      initialState: .init(
        editableImage: .init(cgImageSource: imageSource)
      )
    )
    
    store.commit {
      $0.wrapped.resolve(with: metadata)
    }
    
    pendingAction = { _ in
      return .init {}
    }
  }
  
  /// Creates an instance from UIImage
  ///
  /// - Attention: To reduce memory footprint, as possible creating an instance from url instead.
  public init(image uiImage: UIImage) {
    
    store = .init(
      initialState: .init(
        editableImage: .init(image: uiImage)
      )
    )
    
    store.commit {
      $0.wrapped.resolve(with: .init(orientation: .init(uiImage.imageOrientation), imageSize: .init(image: uiImage)))
    }
    
    pendingAction = { _ in  return .init {} }
    
  }
  
  #endif
  
  /**
   Creates an instance from fileURL.
   This is most efficient way to edit image without large memory footprint.
   */
  public init(
    fileURL: URL
  ) throws {
    guard fileURL.isFileURL else {
      throw ImageProviderError.urlIsNotFileURL(fileURL)
    }
    
    guard let provider = CGDataProvider(url: fileURL as CFURL) else {
      throw ImageProviderError.failedToCreateCGDataProvider
    }
    
    guard let imageSource = CGImageSourceCreateWithDataProvider(provider, nil) else {
      throw ImageProviderError.failedToCreateCGImageSource
    }
    
    guard let metadata = ImageTool.makeImageMetadata(from: imageSource) else {
      throw ImageProviderError.failedToGetImageSize
    }
        
    store = .init(
      initialState: .init(
        editableImage: .init(cgImageSource: imageSource)
      )
    )
    
    store.commit {
      $0.wrapped.resolve(with: metadata)
    }
    
    pendingAction = { _ in return .init {} }
  }
  
  /**
   Creates an instance
   */
  public convenience init(
    editableRemoteURL: URL,
    editableImageSize: CGSize? = nil,
    editableOrientation: CGImagePropertyOrientation? = nil
  ) {
    self.init(
      editableRemoteURLRequest: URLRequest(url: editableRemoteURL),
      editableImageSize: editableImageSize,
      editableOrientation: editableOrientation
    )
  }
  
  public init(
    editableRemoteURLRequest: URLRequest,
    editableImageSize: CGSize? = nil,
    editableOrientation: CGImagePropertyOrientation? = nil
  ) {
    
    store = .init(
      initialState: .init(
        imageSize: editableImageSize,
        orientation: editableOrientation,
        editableImage: nil
      )
    )
    
    pendingAction = { `self` in
      
      let editableTask = URLSession.shared.downloadTask(with: editableRemoteURLRequest) { [weak self] url, response, error in
        
        guard let self = self else { return }
        
        if let error = error {
          self.store.commit {
            $0.loadingFatalErrors.append(.failedToDownloadEditableImage(underlyingError: error))
          }
        }
        
        self.commit { state in
          if let url = url {
            
            guard let provider = CGDataProvider(url: url as CFURL) else {
              state.loadingFatalErrors.append(ImageProviderError.failedToCreateCGDataProvider)
              return
            }
            
            guard let imageSource = CGImageSourceCreateWithDataProvider(provider, nil) else {
              state.loadingFatalErrors.append(ImageProviderError.failedToCreateCGImageSource)
              return
            }
            
            guard let metadata = ImageTool.makeImageMetadata(from: imageSource) else {
              state.loadingNonFatalErrors.append(ImageProviderError.failedToGetImageMetadata)
              return
            }
        
            state.wrapped.resolve(with: metadata)
            state.editableImage = .init(cgImageSource: imageSource)
          }
        }
      }
      
      editableTask.resume()
      
      return .init {
        editableTask.cancel()
      }
    }
  }
  
  #if canImport(Photos)
  
  public init(asset: PHAsset) {
    // TODO: cancellation, Error handeling
    
    store = .init(
      initialState: .init(
        editableImage: nil
      )
    )
    
    pendingAction = { `self` in
      
      let finalImageRequestOptions = PHImageRequestOptions()
      finalImageRequestOptions.deliveryMode = .highQualityFormat
      finalImageRequestOptions.isNetworkAccessAllowed = true
      finalImageRequestOptions.version = .current
      finalImageRequestOptions.resizeMode = .none

     let request = PHImageManager.default().requestImage(
        for: asset,
        targetSize: PHImageManagerMaximumSize,
        contentMode: .aspectFit,
        options: finalImageRequestOptions
      ) { [weak self] image, info in
        
        // FIXME: Avoid loading image, get a url instead.
        
        guard let self = self else { return }
        
        self.commit { state in
          
          if let error = info?[PHImageErrorKey] as? Error {
            state.loadingFatalErrors.append(.failedToDownloadEditableImage(underlyingError: error))
            return
          }
          
          guard let image = image else { return }
          
          state.wrapped.resolve(with: .init(
            orientation: .init(image.imageOrientation),
            imageSize: .init(width: asset.pixelWidth, height: asset.pixelWidth)
          ))
          state.editableImage = .init(image: image)
          
        }
      }
      
      return .init {
        PHImageManager.default().cancelImageRequest(request)
      }
    }
  }
  
  #endif
  
  func start() {
    guard cancellable == nil else { return }
    cancellable = pendingAction(self)
  }
  
  deinit {
    EngineLog.debug("[ImageProvider] deinit")
  }
}
