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
    let speedOfSound: Float = 343.0
    let movementThreshold: Float = 25.0
    let lowestFrequency:Float = 17000
    let highestFrequency:Float = 20000
    let zoomWindow:Int = 120
    let audio = AudioModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE)
    
    var timer: Timer?
    var emittedFrequency: Float = 18500
    var binSize: Float = 0.0
    
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
            let endIdx = min(AudioConstants.AUDIO_BUFFER_SIZE - 1, frequencyIdx + zoom + 1)
            let subArray:[Float] = Array(self.audio.fftData[startIdx...endIdx])
            graph.updateGraph(data: subArray, forKey: "fftZoomed")
    
            // Calculate Doppler
            calcDoppler(fftData: subArray, startIndex: startIdx, windowSize: 10)
        }
    }
    
    // Calculate Doppler Shift And Update Display
    func calcDoppler(fftData: [Float], startIndex: Int, windowSize: Int) {
        // Get Windowed Data Set To Remove Noise
        let windowedData = getWindowedData(fftData: fftData, windowSize: windowSize)
        
        // Get Significant Frequencies
        if let result = getMostSignificantFrequencyIndex(fftData: windowedData) {
            //print("Most significant frequency 1 at index: \(result.frequencyIndex1) with magnitude: \(result.frequencyMagnitude1)")
            //print("Most significant frequency 2 at index: \(result.frequencyIndex2) with magnitude: \(result.frequencyMagnitude2)")

            let movementThreshold: Float = 0.5
            let magnitudeDifference = abs(result.frequencyMagnitude1 - result.frequencyMagnitude2)
            print(magnitudeDifference)
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
    
    // Create Windowed Data Set To Remove Noise
    func getWindowedData(fftData: [Float], windowSize: Int) -> [Float] {
        guard fftData.count >= windowSize else { return fftData }
        
        var windowedData = [Float]()
        for i in 0..<(fftData.count - windowSize) {
            let window = Array(fftData[i..<i+windowSize])
            // Using Max And Not Average As I Want The Biggest Magnitude In The Range
            if let max = window.max() {
                windowedData.append(max)
            }
        }
        return windowedData
    }
    
    // Get The Top 2 Most Significant Frequency Indexes
    func getMostSignificantFrequencyIndex(fftData: [Float]) -> (frequencyIndex1: Int, frequencyMagnitude1: Float, frequencyIndex2: Int, frequencyMagnitude2: Float)? {
          
        var modifiedFftData = fftData
        
        // Get Index Of Max Frequency
        guard let frequencyIndex1 = modifiedFftData.indices.max(by: { abs(modifiedFftData[$0]) < abs(modifiedFftData[$1]) }) else {
            print("ERROR. Cannot Find Frequency 1")
            return nil
        }
        let frequencyMagnitude1 = fftData[frequencyIndex1]
        
        // Zero Out Emitted Frequency So I Do Not Select It
        modifiedFftData[frequencyIndex1] = 0.0
        
        // Get Index Of Next Max Frequency
        guard let frequencyIndex2 = modifiedFftData.indices.max(by: { abs(modifiedFftData[$0]) < abs(modifiedFftData[$1]) }) else {
            print("ERROR. Cannot Find Frequency 2")
            return nil
        }

        let frequencyMagnitude2 = fftData[frequencyIndex2]
        
        return (frequencyIndex1: frequencyIndex1,  frequencyMagnitude1: frequencyMagnitude1, frequencyIndex2: frequencyIndex2, frequencyMagnitude2: frequencyMagnitude2)
    }
   
}

