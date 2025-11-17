//
//  ContentView.swift
//  cha-thai
//
//  Created by Sanpawat Sewsuwan on 15/11/2568 BE.
//

import Combine
import CoreMotion
import PhotosUI
import SwiftUI
import Translation
import Vision

struct ContentView: View {
    @State var keywords: [String] = []
    @State var viewModel = ViewModel()
    @State var selectedImage1: UIImage?
    @State var photoPickerItem1: PhotosPickerItem?
    @State var isLoading = false
    @State var translated: [String] = []
    @State var showNextPage: Bool = false
    @State private var configuration: TranslationSession.Configuration?
    
    let n = 5
    
    var body: some View {
        VStack(spacing: 24) {
            PhotosPicker(selection: $photoPickerItem1, matching: .images) {
                Group {
                    if let selectedImage1 = selectedImage1 {
                        Image(uiImage: selectedImage1)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                            Image(systemName: "photo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 100)
                                .foregroundStyle(.gray.opacity(0.6))
                        }
                    }
                }
            }
            .onChange(of: photoPickerItem1) { oldValue, newValue in
                Task {
                    if let newValue = newValue,
                       let data = try? await newValue.loadTransferable(type: Data.self),
                       let image = UIImage(data: data)
                    {
                        selectedImage1 = image
                    }
                }
            }
            .frame(width: 300, height: 400)
            
            Button {
                Task {
                    isLoading = true
                    keywords = []
                    
                    let result1 = try! await classifyImage(selectedImage1!)
                    
                    let sortedTotalResult = result1.sorted(by: { $0.confidence > $1.confidence })
                    
                    for (i, item) in sortedTotalResult.enumerated() {
                        if i < n {
                            keywords.append(item.label)
                        } else {
                            break
                        }
                    }
                    try! await viewModel.requestWords(keywords: keywords)
                    isLoading = false
                }
            } label: {
                HStack {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else {
                        Text("Start")
                            .font(.custom("ComicRelief-Bold", size: 45))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 300, height: 100)
                .background(
                    LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                )
                .clipShape(Capsule())
                .shadow(color: .black.opacity(0.2), radius: 8)
            }
        }
        .onChange(of: viewModel.result?.words) { oldValue, newValue in
            if configuration == nil {
                configuration = TranslationSession.Configuration(
                    source: .init(identifier: "en-US"), target: .init(identifier: "th-TH"))
                return
            }
            
            configuration?.invalidate()
        }
        .translationTask(configuration) { session in
            translated.removeAll()

            let words = viewModel.result?.words ?? []
            let requests = words.map { TranslationSession.Request(sourceText: $0, clientIdentifier: $0) }
            
            if let responses = try? await session.translations(from: requests) {
                
                responses.forEach { response in
                    updateTranslation(response: response)
                }
            }
        }
        .onChange(
            of: translated,
            { oldValue, newValue in
                if newValue.count == 10 {
                    showNextPage.toggle()
                }
            }
        )
        .fullScreenCover(isPresented: $showNextPage) {
            QuizView(translatedWords: translated, words: keywords)
        }
    }
    
    func updateTranslation(response: TranslationSession.Response) {
        let words = viewModel.result?.words ?? []
        guard words.firstIndex(where: { $0 == response.clientIdentifier }) != nil else {
            return
        }
        
        translated.append(response.targetText)
    }
    
    private func classifyImage(_ image: UIImage) async throws -> [(label: String, confidence: Float)]
    {
        let observations = try await classify(image)
        if let observations = observations {
            return filterIdentifiers(from: observations)
        }
        
        return []
    }
    
    func classify(_ image: UIImage) async throws -> [ClassificationObservation]? {
        guard let image = CIImage(image: image) else {
            return nil
        }
        
        do {
            let request = ClassifyImageRequest()
            
            let results = try await request.perform(on: image)
            return results
        } catch {
            print("Encountered an error when performing the request: \(error.localizedDescription)")
        }
        
        return nil
    }
    
    private func filterIdentifiers(from observations: [ClassificationObservation]) -> [(
        String, Float
    )] {
        
        var filteredIdentifiers = [(String, Float)]()
        
        for observation in observations {
            if observation.confidence > 0.1 {
                filteredIdentifiers.append((observation.identifier, observation.confidence))
            }
        }
        
        return filteredIdentifiers
    }
}

class MotionManager: ObservableObject {
    private let motionManager = CMMotionManager()
    @Published var backgroundColor: Color = .white
    @Published var shouldAdvance: Bool = false
    
    private var lastOrientation: Double = 0
    private var isProcessing: Bool = false
    
    func startMotionUpdates() {
        guard motionManager.isDeviceMotionAvailable else {
            print("Device motion is not available")
            return
        }
        
        motionManager.deviceMotionUpdateInterval = 0.1
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            guard let self = self, let motion = motion, !self.isProcessing else { return }
            
            let attitude = motion.attitude
            let roll = attitude.roll

            let rollDegrees = roll * 180.0 / .pi
                        
            if abs(roll) < 0.52 && abs(roll - self.lastOrientation) > 0.3 {
                self.isProcessing = true
                self.backgroundColor = .red
                self.lastOrientation = roll
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.shouldAdvance = true
                    self.backgroundColor = .white
                    self.isProcessing = false
                }
            }
            else if (abs(roll - .pi) < 0.52 || abs(roll + .pi) < 0.52)
                        && abs(roll - self.lastOrientation) > 0.3
            {
                self.isProcessing = true
                self.backgroundColor = .green
                self.lastOrientation = roll
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.shouldAdvance = true
                    self.backgroundColor = .white
                    self.isProcessing = false
                }
            }
        }
    }
    
    func stopMotionUpdates() {
        motionManager.stopDeviceMotionUpdates()
    }
}

struct QuizView: View {
    let translatedWords: [String]
    let words: [String]
    @State private var currentIndex = 0
    @StateObject private var motionManager = MotionManager()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            motionManager.backgroundColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: motionManager.backgroundColor)
            
            if currentIndex < translatedWords.count {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()

                        VStack(spacing: 0) {
                            Text(translatedWords[currentIndex])
                                .font(.custom("Kanit-SemiBold", size: 100))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                            Text(words[currentIndex])
                                .font(.custom("Kanit-SemiBold", size: 80))
                                .foregroundColor(.gray)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        
                        Spacer()
                    }
                    Spacer()
                }
            } else {
                HStack {
                    Spacer()
                    Text("Complete!")
                        .font(.custom("Kanit-SemiBold", size: 100))
                        .foregroundColor(.black)
                    Spacer()
                }
            }
            
            Button("Close") {
                dismiss()
            }
            .font(.custom("Kanit-Regular", size: 32))
            .buttonStyle(.glass)
            .padding()
        }
        .onAppear {
            motionManager.startMotionUpdates()
        }
        .onDisappear {
            motionManager.stopMotionUpdates()
        }
        .onChange(of: motionManager.shouldAdvance) { oldValue, newValue in
            if newValue && currentIndex < translatedWords.count - 1 {
                currentIndex += 1
                motionManager.shouldAdvance = false
            } else if newValue && currentIndex == translatedWords.count - 1 {
                dismiss()
            }
        }
    }
}

#Preview {
//    ContentView()
    QuizView(translatedWords: ["สวัสดี"], words: ["Hello"])
}
