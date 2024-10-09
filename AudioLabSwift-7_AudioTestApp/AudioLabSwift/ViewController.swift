
//  Created by Eric Larson 
//  Copyright © 2020 Eric Larson. All rights reserved.


import UIKit
import Metal


class ViewController: UIViewController {

    @IBOutlet weak var userView: UIView!  // to display graph
    
    
    // to hold constant buffer size = 4096
    struct AudioConstants{
        static let AUDIO_BUFFER_SIZE = 1024*4
    }
    
    let audio = AudioModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE,lookback:45)   // setup audio model with the buffer size
    
    // to display metal graph
    lazy var graph:MetalGraph? = {
        return MetalGraph(userView: self.userView)
    }()
    
    var timer:Timer? = nil  // Timer property does not hold any value initially
    
    // initial value of frequency to be 300. "didSet" property observer updates the frequency, "labelFX" text when the frequency changes
    var frequency1:Float = 300 {
        didSet{
            audio.sineFrequency1 = frequency1
            labelF1.text = "F1: \(frequency1)"
        }
    }
    var frequency2:Float = 300 {
        didSet{
            audio.sineFrequency2 = frequency2
            labelF2.text = "F2: \(frequency2)"
        }
    }
    var frequency3:Float = 300 {
        didSet{
            audio.sineFrequency3 = frequency3
            labelF3.text = "F3: \(frequency3)"
        }
    }
    
    
    // to display frequency1, frequency2 and frequency3
    @IBOutlet weak var labelF1: UILabel!
    @IBOutlet weak var labelF2: UILabel!
    @IBOutlet weak var labelF3: UILabel!
    
    // action for setting frequency2 close to frequency1 based on the given conditions
    @IBAction func setClose(_ sender: Any) {
        let diff = abs(frequency1-frequency2)
        if diff > 100 {
            frequency2 = frequency1 + 99
        }else if diff > 60{
            frequency2 = frequency1 + 51
        }else if diff > 30{
            frequency2 = frequency1 + 10
        }else{
            frequency2 = frequency1 + 300
        }
    }
    
    // action to toggle the pulsing state in audio model based on switch's state
    @IBAction func shouldPulse(_ sender: UISwitch) {
        audio.pulsing = sender.isOn
    }
    
    // actions to update frequency1, frequency2, and frequency3 based on the slider values
    @IBAction func sliderF1(_ sender: UISlider) {
        frequency1 = sender.value
    }
    @IBAction func sliderF2(_ sender: UISlider) {
        frequency2 = sender.value
    }
    @IBAction func sliderF3(_ sender: UISlider) {
        frequency3 = sender.value
    }
    
    // set the initial values of the frequencies
    override func viewDidLoad() {
        super.viewDidLoad()
        frequency1 = 18000
        frequency2 = 18500
        frequency3 = 19000
    }
    
    
    // call before the view becomes visible
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // configure graph if available
        if let graph = self.graph{
            graph.setBackgroundColor(r: 0, g: 0, b: 0, a: 1)   //set background color to be black
            graph.addGraph(withName: "time", numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)  //add time-domain graph
            graph.addGraph(withName: "fft", shouldNormalizeForFFT: true, numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE/2)  //add main fft graph
            graph.addGraph(withName: "fftZoomed", shouldNormalizeForFFT: true, numPointsInGraph: 300) // add zoomed fft graph. 300 points to display
            graph.makeGrids()   // add grids to graph
        }

        audio.startMicrophoneProcessing(withFps: 20)  // start audio processing at 20 Fps
        audio.play()   // start audio playback
        
        // run the loop for updating the graph peridocially (every 0.05 s)
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            self.updateGraph()
        }
    }
    
    
    // call after view disappears
    override func viewDidDisappear(_ animated: Bool) {
        timer?.invalidate()   //invalidate the timer
        graph?.teardown()     // teardown the graph
        graph = nil           //set the graph to nil
        audio.stop()          // stop audio processing
        super.viewDidDisappear(animated)
    }
    
    
    // periodically, update the graph with refreshed time-domain data , FFT Data
    func updateGraph(){
        
        // if graph is available
        if let graph = self.graph{
            
            // update the time graph
            graph.updateGraph(
                data: self.audio.timeData,
                forKey: "time"
            )
            
            //update the fft graph
            graph.updateGraph(
                data: self.audio.fftData,
                forKey: "fft"
            )
      
            let minfreq = min(min(frequency1,frequency2),frequency3)   // find min frequency from all three frequencies
            let startIdx:Int = (Int(minfreq)-50) * AudioConstants.AUDIO_BUFFER_SIZE/audio.samplingRate  // determine starting index for fft data to be zoomed in
            let subArray:[Float] = Array(self.audio.fftData[startIdx...startIdx+300])  //subarray to reprsent zoomed-in of the fft data
            
            // update fftZoomed graph
            graph.updateGraph(
                data: subArray,
                forKey: "fftZoomed"
            )
        }
    }

}

