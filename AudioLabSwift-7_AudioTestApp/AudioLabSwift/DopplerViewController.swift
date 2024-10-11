import UIKit
import Metal

struct AudioConstants{
    static let AUDIO_BUFFER_SIZE = 1024 * 4
    static let AUDIO_BUFFER_SIZE_FLOAT : Float = Float(AUDIO_BUFFER_SIZE)
}

class DopplerViewController: UIViewController {
    
    // UI Components
    @IBOutlet weak var frequencySlider: UISlider!
    @IBOutlet weak var frequencyLabel: UILabel!
    @IBOutlet weak var directionLabel: UILabel!
    @IBOutlet weak var graphView: UIView!
    
    // Member Variables
    let movementThreshold: Float = 25.0
    let lowestFrequency:Float = 17000
    let highestFrequency:Float = 20000
    let zoomWindow:Int = 50
    let audio = AudioModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE)
    
    var timer: Timer?
    var emittedFrequency: Float = 18500
    var binSize: Float = 0.0
    var historyArray = [String](repeating: "no shift", count: 5)
    var currentIndex = 0
    
    // Properties
    lazy var graph:MetalGraph? = {
        return MetalGraph(userView: self.graphView)
    }()
    
    // View Controller Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set Frequency Min and Max Values
        frequencySlider.minimumValue = self.lowestFrequency / 1000
        frequencySlider.maximumValue = self.highestFrequency / 1000
        frequencySlider.value = self.emittedFrequency / 1000 //Convert To Slider Scale
        frequencyLabel.text = "\(frequencySlider.value) kHz"
        
        // Set Direction Label
        directionLabel.text = "Waiting For Input"
        
        // Setup Graphs
        if let graph = self.graph{
            graph.setBackgroundColor(r: 0, g: 0, b: 0, a: 1)
            
            graph.addGraph(withName: "fftZoomed",
                           shouldNormalizeForFFT: true,
                           numPointsInGraph: self.zoomWindow)
            
            graph.addGraph(withName: "fft",
                           shouldNormalizeForFFT: true,
                           numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE / 2)
            
            graph.addGraph(withName: "time",
                           numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)
            
            graph.makeGrids()
        }
        
        // Enable Microphone
        audio.startMicrophoneProcessing(withFps: 20)
        
        // Start Audio
        audio.startProcessingSinewaveForPlayback(withFreq: self.emittedFrequency)
        audio.play()
                
        // Calc Bin Size
        self.binSize = Float(self.audio.samplingRate) / AudioConstants.AUDIO_BUFFER_SIZE_FLOAT
        
        // Configure And Start Timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.updateGraph()
        }
    }
    // call after view disappears
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        // Disable Timer
        timer?.invalidate()
        timer = nil
        
        // Remove Graph
        graph?.teardown()
        graph = nil
        
        // Stop Audio
        audio.stop()
    }
    
    // Slider Changed Event Updates UI and Frequency
    @IBAction func sliderValueChanged(_ sender: UISlider) {
        let sliderValue = round(sender.value * 10) / 10
        let frequency = sliderValue * 1000
        
        // Update Label Based On Slider Value
        frequencyLabel.text = "\(sliderValue) kHz"
        
        // Change Output Frequency
        self.emittedFrequency = frequency
        audio.sineFrequency = self.emittedFrequency
    }
    
    // Update Graph Based On Timer
    func updateGraph() {
        if let graph = self.graph {
            
            // Update the time-domain graph
            graph.updateGraph(data: self.audio.timeData, forKey: "time")
            
            // Update the full FFT graph
            graph.updateGraph(data: self.audio.fftData, forKey: "fft")
            
            // Window Data Using Current Emitted Frequency And Zoom
            // Divide Window Evenly Before And After Emitted Frequency
            // Assumption Is That The Shift To Measured Will Not Be Extreme
            let zoom: Int = self.zoomWindow / 2
            let frequencyIdx = Int(self.emittedFrequency * Float(AudioConstants.AUDIO_BUFFER_SIZE) / Float(audio.samplingRate))
            let startIdx = max(0, frequencyIdx - zoom)
            let endIdx = min(AudioConstants.AUDIO_BUFFER_SIZE - 1, frequencyIdx + zoom - 1)
            let subArray:[Float] = Array(self.audio.fftData[startIdx...endIdx])
            graph.updateGraph(data: subArray, forKey: "fftZoomed")
    
            // Calculate Doppler
            calcShift(fftData: self.audio.fftData, windowSize: zoom)
        }
    }
    
    // Calculate The Dopler Shift
    func calcShift(fftData: [Float], windowSize: Int) {
        guard !fftData.isEmpty else { return }
        
        // Get Index Of Emitted Frequency
        let frequencyResolution = Float(audio.samplingRate) / Float(AudioConstants.AUDIO_BUFFER_SIZE)
        let frequencyIdx = Int(self.emittedFrequency / frequencyResolution)
          
        // Get Left And Right Magnitudes And Compare
        if let bandwidth = getFrequencyMagnitudes(fftData: fftData, emitFrequencyIndex: frequencyIdx, windowSize: windowSize) {
            
            let leftBandwidth = bandwidth.left
            let rightBandwidth = bandwidth.right

            // Compare Strength And Update Result
            var result: String
            if abs(bandwidth.left - bandwidth.right) <= 2 {
                print("No Movement. Left Count: \(bandwidth.left). Right Count: \(bandwidth.right)")
                result = "No Movement"
            } else if rightBandwidth > leftBandwidth {
                print("Moving Toward. Left Count: \(bandwidth.left). Right Count: \(bandwidth.right)")
                result = "Moving Toward"
            } else {
                print("Moving Away. Left Count: \(bandwidth.left). Right Count: \(bandwidth.right)")
                result = "Moving Away"
            }
            
            historyArray[currentIndex] = result
            currentIndex = (currentIndex + 1) % historyArray.count
            
            // Show More Frequenct Action
            directionLabel.text = getMostFrequenctAction()
        }
    }
    
    // Use Bin Counting To Determine The Strength Of The Frequencies To The Left And Right Of The Emitted Frequency
    func getFrequencyMagnitudes(fftData: [Float], emitFrequencyIndex: Int, windowSize: Int) -> (left: Int, right: Int)? {
        guard !fftData.isEmpty, emitFrequencyIndex >= 0, emitFrequencyIndex < fftData.count else { return nil }
        
        let primaryVolume = fftData[emitFrequencyIndex]
        var leftCount = 0
        var rightCount = 0
        
        // This Is Trial And Error - Mostly Error
        let maxVolumeRatio: Float = 0.85
        
        // Deterine The Number Of Bins/Indexes That Have A Significant
        while leftCount < windowSize {
            let volume = fftData[emitFrequencyIndex - leftCount]
            let normalizedVolume = volume / primaryVolume
            
            if normalizedVolume < maxVolumeRatio { break }

            leftCount += 1
            
            if emitFrequencyIndex - leftCount <= 0 { break }
        }
        
        while rightCount < windowSize {
            let volume = fftData[emitFrequencyIndex + rightCount]
            let normalizedVolume = volume / primaryVolume
            
            if normalizedVolume < maxVolumeRatio { break }
            
            rightCount += 1
            
            if emitFrequencyIndex + rightCount >= fftData.count { break }
        }
        
        return (left: leftCount, right: rightCount)
    }
    
    // Get Most Frequent Recent Action Favoring Toward And Away
    func getMostFrequenctAction() -> String {
        var noShiftCount = 0
        var towardCount = 0
        var awayCount = 0
            
        for action in historyArray {
            if action == "No Movement" {
                noShiftCount += 1
            } else if action == "Moving Toward" {
                towardCount += 1
            } else if action == "Moving Away" {
                awayCount += 2
            }
        }

        if awayCount > towardCount && awayCount > noShiftCount {
            return "Moving Away"
        } else if towardCount > awayCount && towardCount > noShiftCount {
            return "Moving Toward"
        } else {
            return "No Movement"
        }
    }
    
    // Create Windowed Data Set To Remove Noise
    func getWindowedData(fftData: [Float], windowSize: Int) -> [Float] {
        guard fftData.count >= windowSize else { return fftData }
        
        var windowedData = [Float]()
        for i in 0..<(fftData.count - windowSize) {
            let window = Array(fftData[i..<i+windowSize])
            // Using Max And Not Average As I Want The Biggest Magnitude In The Range
           // if let max = window.max() {
            //    windowedData.append(max)
            //}
            
            let average = window.reduce(0, +) / Float(window.count)
            windowedData.append(average)
        }
        return windowedData
    }
    
    
    // Split FFT Data Into Three Segments: Left, Middle, And Right
    // Each Segment Will Contain The Max Magnitude In That Region
    // Middle Contains The Emitted Frequency (Middle Of The Array)
    // Idea Is To Compare The Left And Right To Determine Which One Contains The Largest Peak
    func consolidateFFTData(fftData: [Float]) -> (left: Float, middle: Float, right: Float) {
        // Ensure there is enough data to consolidate
        guard fftData.count >= 3 else {
            print("Error: Not enough data to consolidate.")
            return (0, 0, 0)
        }
     
        // Split Data 47.5%, 5%, 47.5%
        // The Magnitudes In The Middle Near The Emitted Frequency Are All The Same Or Close To Each Other
        // Basically, I Am Removing Those Values
        let leftSize = Int(Float(fftData.count) * 0.45)
        let middleSize = Int(Float(fftData.count) * 0.1)
        let rightSize = fftData.count - leftSize - middleSize

        let leftPart = Array(fftData[0..<leftSize])
        let middlePart = Array(fftData[leftSize..<(leftSize + middleSize)])
        let rightPart = Array(fftData[(leftSize + middleSize)..<fftData.count])
        
        // Use Max TO Find The Peaks
        let leftMax = (leftPart.max() ?? 0.0)
        let middleMax = (middlePart.max() ?? 0.0)
        let rightMax = (rightPart.max() ?? 0.0)

        //let leftMax = leftPart.reduce(0, +) / Float(leftPart.count)
        //let middleMax = middlePart.reduce(0, +) / Float(middlePart.count)
        //let rightMax = rightPart.reduce(0, +) / Float(rightPart.count)

        return (leftMax, middleMax, rightMax)
    }

    // Original Method. Too Much Noise. The Direction "Fluttered" And I Could Not Figure Out How To Compensate
    func calcDoppler1(fftData: [Float], startIndex: Int, windowSize: Int) {
         // Get Windowed Data Set To Remove Noise
         let windowedData = getWindowedData(fftData: fftData, windowSize: windowSize)
         
         // Get Significant Frequencies
         if let result = getMostSignificantFrequencyIndex(fftData: windowedData) {
             print("Most significant frequency 1 at index: \(result.frequencyIndex1) with magnitude: \(result.frequencyMagnitude1)")
             print("Most significant frequency 2 at index: \(result.frequencyIndex2) with magnitude: \(result.frequencyMagnitude2)")

             let movementThreshold: Float = 8.0
             let magnitudeDifference = abs(result.frequencyMagnitude1 - result.frequencyMagnitude2)

             if magnitudeDifference > movementThreshold {
                 // Frequency 1 Is To The Right Of Frequency 2
                 // Frequency Shift Is Lower. Microphone Moving Away From Object
                 if result.frequencyIndex1 > result.frequencyIndex2 {
                     directionLabel.text = "Moving Away"
                 }
                 // Frequency 1 Is To The Left Of Frequency 2
                 // Frequency Shift Is Higher. Microphone Moving Toward Object
                 else {
                     directionLabel.text = "Moving Toward"
                 }
             }
             else {
                 directionLabel.text = "No Significant Movement"
             }
         } else {
             print("ERROR. No Frequencies Found")
         }
    }
    
    // Old Function. Part Of Original Attempt To Find Peaks In The Data
    func getMostSignificantFrequencyIndex(fftData: [Float]) -> (frequencyIndex1: Int, frequencyMagnitude1: Float, frequencyIndex2: Int, frequencyMagnitude2: Float)? {
          
        var modifiedFftData = fftData
        
        // Get Index Of Max Frequency
        guard let frequencyIndex1 = modifiedFftData.indices.max(by: { modifiedFftData[$0] < modifiedFftData[$1] }) else {
            print("ERROR. Cannot Find Frequency 1")
            return nil
        }
        let frequencyMagnitude1 = modifiedFftData[frequencyIndex1]
        
        // Zero Out Emitted Frequency So I Do Not Select It
        //modifiedFftData[frequencyIndex1] = -999999
        let range = 10
        let replacementValue: Float = -999999
        for i in (frequencyIndex1 - range)...(frequencyIndex1 + range) {
            // Check if the index is within bounds of the array
            if i >= 0 && i < modifiedFftData.count {
                modifiedFftData[i] = replacementValue
            }
        }
        // Get Index Of Next Max Frequency
        guard let frequencyIndex2 = modifiedFftData.indices.max(by: { modifiedFftData[$0] < modifiedFftData[$1] }) else {
            print("ERROR. Cannot Find Frequency 2")
            return nil
        }

        let frequencyMagnitude2 = modifiedFftData[frequencyIndex2]
        
        return (frequencyIndex1: frequencyIndex1,  frequencyMagnitude1: frequencyMagnitude1, frequencyIndex2: frequencyIndex2, frequencyMagnitude2: frequencyMagnitude2)
    }
   
}

