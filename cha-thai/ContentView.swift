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
    @State var selectedImageIndex: Int?
    @State var photoPickerItem1: PhotosPickerItem?
    @State var isLoading = false
    @State var translated: [String] = []
    @State var showNextPage: Bool = false
    @State private var configuration: TranslationSession.Configuration?
    
    @State private var offset = CGFloat.zero
    
    let n = 5
    @State var cardImages = [
        UIImage(named: "cat")!, UIImage(named: "dog")!, UIImage(named: "camping")!, UIImage(named: "house")!, UIImage(named: "mountain")!,
    ]
    
    var body: some View {
        ZStack {
            Image("background")
                .resizable()
                .opacity(0.2)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        selectedImageIndex = nil
                    }
                }
                .ignoresSafeArea()
            
            VStack(spacing: 12) {
                Spacer()
                
                Text("Guess the Word ")
                    .font(.custom("Kanit-SemiBold", size: 86))

                ScrollView(.horizontal) {
                    HStack(spacing: -30) {
                        PhotosPicker(selection: $photoPickerItem1, matching: .images) {
                            ZStack {
                                Rectangle()
                                    .fill(Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255))
                                Image(systemName: "plus")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 100)
                                    .foregroundStyle(.gray)
                            }
                            .frame(width: 300, height: 400)
                            .clipShape(.rect(cornerRadius: 24))
                            .shadow(radius: 4)
                            .rotation3DEffect(Angle(degrees: offset), axis: (x: 0, y: 1, z: 0))
                            .onChange(of: photoPickerItem1) { oldValue, newValue in
                                Task {
                                    if let newValue = newValue,
                                       let data = try? await newValue.loadTransferable(type: Data.self),
                                       let image = UIImage(data: data)
                                    {
                                        withAnimation {
                                            selectedImageIndex = nil
                                            cardImages.insert(image, at: 0)
                                        }
                                    }
                                }
                            }
                        }
                        .zIndex(99)
                        
                        ForEach(cardImages.enumerated(), id: \.offset) { i, image in
                            VStack {
                                Button(
                                    action: {
                                        withAnimation {
                                            selectedImageIndex = i
                                        }
                                    },
                                    label: {
                                        Image(uiImage: image)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 300, height: 400)
                                            .clipShape(.rect(cornerRadius: 24))
                                            .shadow(radius: 4)
                                    })
                                
                                if selectedImageIndex == i {
                                    Button {
                                        Task {
                                            isLoading = true
                                            keywords = []
                                            
                                            let result1 = try! await classifyImage(image)
                                            
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
                                                    .font(.custom("Kanit-SemiBold", size: 32))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .frame(width: 200, height: 80)
                                        .background(
                                            LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom)
                                        )
                                        .clipShape(Capsule())
                                        .shadow(color: .black.opacity(0.2), radius: 8)
                                    }
                                }
                            }
                            .rotation3DEffect(Angle(degrees: offset), axis: (x: 0, y: 1, z: 0))
                            .scaleEffect(
                                selectedImageIndex == i
                                ? CGSize(width: 1.2, height: 1.2) : CGSize(width: 1.0, height: 1.0)
                            )
                            .offset(y: selectedImageIndex == i ? -60 : 0)
                            .zIndex(selectedImageIndex == i ? 100 : Double(10 - i))
                        }
                    }
                    .background(
                        GeometryReader { proxy -> Color in
                            DispatchQueue.main.async {
                                let x =
                                -(proxy.frame(in: .named("scroll")).origin.x - 200.0)
                                / UIScreen.main.bounds.size.width
                                
                                offset = x * -15.0
                            }
                            return Color.clear
                        }
                    )
                    .padding(.horizontal, 80)
                }
                .scrollClipDisabled()
                .coordinateSpace(name: "scroll")
                .scrollIndicators(.hidden)
                
                Spacer()
                
                Spacer()
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
                    selectedImageIndex = nil
                    showNextPage.toggle()
                }
            }
        )
        .fullScreenCover(isPresented: $showNextPage) {
            QuizView(translatedWords: translated, words: viewModel.result?.words ?? [])
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
    @Published var backgroundColor: Color = .clear
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
                    self.backgroundColor = .clear
                    self.isProcessing = false
                }
            } else if (abs(roll - .pi) < 0.52 || abs(roll + .pi) < 0.52)
                        && abs(roll - self.lastOrientation) > 0.3
            {
                self.isProcessing = true
                self.backgroundColor = .green
                self.lastOrientation = roll
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.shouldAdvance = true
                    self.backgroundColor = .clear
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
    @State private var timeRemaining = 45
    @State private var timer: Timer?
    @State private var correctWords: [String] = []
    @State private var wrongWords: [String] = []
    @State private var showResults = false
    @State private var isGameActive = true
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            Image("background")
                .resizable()
                .opacity(0.2)
                .ignoresSafeArea()
            
            motionManager.backgroundColor
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.3), value: motionManager.backgroundColor)
            
            if currentIndex < translatedWords.count && isGameActive {
                VStack {
                    HStack {
                        Spacer()
                        Text("\(timeRemaining)")
                            .font(.custom("Kanit-SemiBold", size: 60))
                            .foregroundColor(timeRemaining <= 10 ? .red : .black)
                            .padding()
                    }
                    
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
                    
                    Spacer()
                    Spacer()
                }
            }
        }
        .onAppear {
            motionManager.startMotionUpdates()
            startTimer()
        }
        .onDisappear {
            stopTimer()
            motionManager.stopMotionUpdates()
        }
        .onChange(of: motionManager.backgroundColor) { oldValue, newValue in
            if newValue == .green && currentIndex < translatedWords.count && isGameActive {
                correctWords.append(translatedWords[currentIndex])
                
                currentIndex += 1
                motionManager.shouldAdvance = false
            } else if newValue == .red && currentIndex < translatedWords.count && isGameActive {
                wrongWords.append(translatedWords[currentIndex])
                
                currentIndex += 1
                motionManager.shouldAdvance = false
            }
            
            if currentIndex >= words.count {
                endGame()
            }
        }
        .sheet(isPresented: $showResults) {
            ResultsView(
                correctWords: correctWords,
                wrongWords: wrongWords,
                totalWords: translatedWords.count
            )
        }
        .onChange(of: showResults) { oldValue, newValue in
            // When ResultsView is dismissed (showResults becomes false), dismiss QuizView
            if oldValue == true && newValue == false {
                dismiss()
            }
        }
    }
    
    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            if timeRemaining > 0 && isGameActive {
                timeRemaining -= 1
            } else if timeRemaining == 0 && isGameActive {
                endGame()
            }
        }
    }
    
    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
    
    private func endGame() {
        isGameActive = false
        stopTimer()
        motionManager.stopMotionUpdates()
        
        // Mark any remaining words as wrong
        for i in currentIndex..<words.count {
            if !correctWords.contains(translatedWords[i]) && !wrongWords.contains(translatedWords[i]) {
                wrongWords.append(translatedWords[i])
            }
        }
        
        showResults = true
    }
}

struct ResultsView: View {
    let correctWords: [String]
    let wrongWords: [String]
    let totalWords: Int
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Game Over!")
                    .font(.custom("Kanit-SemiBold", size: 48))
                    .foregroundColor(.black)
                    .padding(.top, 40)
                
                Text("Score: \(correctWords.count)/\(totalWords)")
                    .font(.custom("Kanit-SemiBold", size: 32))
                    .foregroundColor(.black)
                
                if !correctWords.isEmpty {
                    VStack(spacing: 12) {
                        Text("Correct Words (\(correctWords.count))")
                            .font(.custom("Kanit-SemiBold", size: 24))
                            .foregroundColor(.green)
                        
                        ForEach(correctWords, id: \.self) { word in
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text(word)
                                    .font(.custom("Kanit-Regular", size: 28))
                                    .foregroundColor(.black)
                            }
                            .padding(.leading, 16)
                        }
                    }
                    .padding()
                }
                
                if !wrongWords.isEmpty {
                    VStack(spacing: 12) {
                        Text("Wrong Words (\(wrongWords.count))")
                            .font(.custom("Kanit-SemiBold", size: 24))
                            .foregroundColor(.red)
                        
                        ForEach(wrongWords, id: \.self) { word in
                            HStack {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text(word)
                                    .font(.custom("Kanit-Regular", size: 28))
                                    .foregroundColor(.black)
                            }
                            .padding(.leading, 16)
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
        .scrollIndicators(.hidden)
    }
}

#Preview {
    ContentView()
    //    QuizView(translatedWords: ["สวัสดี"], words: ["Hello"])
    //    ResultsView(correctWords: ["Hello"], wrongWords: ["สวัสดี"], totalWords: 2)
}
