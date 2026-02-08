import SwiftUI

/// A fullscreen zoomable image viewer with pinch-to-zoom and pan gestures
struct ZoomableImageViewer: View {
    let attachments: [Attachment]
    @Binding var selectedIndex: Int
    @Binding var isPresented: Bool
    
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var dragOffset: CGSize = .zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()
                .opacity(1.0 - Double(abs(dragOffset.height)) / 300.0)
            
            // Image pager
            TabView(selection: $selectedIndex) {
                ForEach(Array(attachments.enumerated()), id: \.element.id) { index, attachment in
                    ZoomableImage(
                        attachment: attachment,
                        scale: index == selectedIndex ? $scale : .constant(1.0),
                        offset: index == selectedIndex ? $offset : .constant(.zero),
                        lastScale: index == selectedIndex ? $lastScale : .constant(1.0),
                        lastOffset: index == selectedIndex ? $lastOffset : .constant(.zero),
                        minScale: minScale,
                        maxScale: maxScale
                    )
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(y: dragOffset.height)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        // Only allow vertical drag when not zoomed
                        if scale <= 1.0 {
                            dragOffset = value.translation
                        }
                    }
                    .onEnded { value in
                        if scale <= 1.0 && abs(value.translation.height) > 100 {
                            withAnimation(.easeOut(duration: 0.2)) {
                                isPresented = false
                            }
                        } else {
                            withAnimation(.spring(response: 0.3)) {
                                dragOffset = .zero
                            }
                        }
                    }
            )
            
            // UI overlay
            VStack {
                // Top bar
                HStack {
                    Spacer()
                    
                    Button {
                        withAnimation(.easeOut(duration: 0.2)) {
                            isPresented = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3)
                            .fontWeight(.medium)
                            .foregroundStyle(.white)
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial.opacity(0.8))
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 16)
                    .padding(.top, 8)
                }
                
                Spacer()
                
                // Page indicator
                if attachments.count > 1 {
                    HStack(spacing: 8) {
                        ForEach(0..<attachments.count, id: \.self) { index in
                            Circle()
                                .fill(index == selectedIndex ? Color.white : Color.white.opacity(0.4))
                                .frame(width: 8, height: 8)
                        }
                    }
                    .padding(.bottom, 40)
                }
            }
        }
        .statusBarHidden()
        .onChange(of: selectedIndex) { _, _ in
            // Reset zoom when changing images
            withAnimation(.spring(response: 0.3)) {
                scale = 1.0
                lastScale = 1.0
                offset = .zero
                lastOffset = .zero
            }
        }
    }
}

/// Individual zoomable image with gesture handling
struct ZoomableImage: View {
    let attachment: Attachment
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    @Binding var lastScale: CGFloat
    @Binding var lastOffset: CGSize
    let minScale: CGFloat
    let maxScale: CGFloat
    
    var body: some View {
        GeometryReader { geometry in
            AuthenticatedImage(url: attachment.imageURL, contentMode: .fit) {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(1.5)
            } errorView: { error in
                VStack(spacing: 12) {
                    Image(systemName: errorIcon(for: error))
                        .font(.system(size: 48))
                        .foregroundStyle(.white.opacity(0.6))
                    Text(errorMessage(for: error))
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .scaleEffect(scale)
            .offset(offset)
            .frame(width: geometry.size.width, height: geometry.size.height)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in
                        let newScale = lastScale * value
                        scale = min(max(newScale, minScale), maxScale)
                    }
                    .onEnded { _ in
                        lastScale = scale
                        if scale <= minScale {
                            withAnimation(.spring(response: 0.3)) {
                                offset = .zero
                                lastOffset = .zero
                            }
                        }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        if scale > 1.0 {
                            offset = CGSize(
                                width: lastOffset.width + value.translation.width,
                                height: lastOffset.height + value.translation.height
                            )
                        }
                    }
                    .onEnded { _ in
                        lastOffset = offset
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.spring(response: 0.3)) {
                    if scale > 1.0 {
                        scale = 1.0
                        lastScale = 1.0
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        scale = 2.5
                        lastScale = 2.5
                    }
                }
            }
        }
    }
    
    private func errorIcon(for error: Error) -> String {
        if let imageError = error as? ImageLoadError {
            switch imageError {
            case .httpError(401), .httpError(403), .authenticationRequired:
                return "lock.fill"
            default:
                return "photo"
            }
        }
        return "photo"
    }
    
    private func errorMessage(for error: Error) -> String {
        if let imageError = error as? ImageLoadError {
            switch imageError {
            case .httpError(401), .httpError(403), .authenticationRequired:
                return "Login required to view image"
            default:
                return "Failed to load image"
            }
        }
        return "Failed to load image"
    }
}

#Preview {
    @Previewable @State var isPresented = true
    @Previewable @State var selectedIndex = 0
    
    ZoomableImageViewer(
        attachments: [
            Attachment(
                downloadUrl: "https://placekitten.com/800/600",
                thumbnailUrl: nil,
                filename: "cat1.jpg",
                mediaType: "image",
                attachmentIndex: 0
            ),
            Attachment(
                downloadUrl: "https://placekitten.com/600/800",
                thumbnailUrl: nil,
                filename: "cat2.jpg",
                mediaType: "image",
                attachmentIndex: 1
            )
        ],
        selectedIndex: $selectedIndex,
        isPresented: $isPresented
    )
}
