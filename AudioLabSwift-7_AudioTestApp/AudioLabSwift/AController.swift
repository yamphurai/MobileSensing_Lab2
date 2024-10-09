//
//  AController.swift
//  AudioLabSwift
//
//  Created by Arman Kamal on 10/8/24.
//  Copyright © 2024 Eric Larson. All rights reserved.
//

import UIKit

class AController: UIViewController {
    
    @IBOutlet weak var label1: UILabel!
    
    @IBOutlet weak var label2: UILabel!
  
    @IBOutlet weak var vowelSound: UILabel!
    
    @IBOutlet weak var graphView: UIView!
    
    lazy var graph:MetalGraph? = {
        return MetalGraph(userView: self.graphView)
    }()
    
    struct AudioConstants {
        static let AUDIO_BUFFER_SIZE = 1024 * 32
    }
    
    let audio = AudioModel(buffer_size: AudioConstants.AUDIO_BUFFER_SIZE,lookback: 45)

    override func viewDidLoad() {
        super.viewDidLoad()
        
        graph?.addGraph(withName: "fft",
            shouldNormalizeForFFT: true,
            numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE / 2)
        graph?.addGraph(withName: "time",
            numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)
        
        graph?.addGraph(withName: "timeUnfrozen",
            numPointsInGraph: AudioConstants.AUDIO_BUFFER_SIZE)
        audio.startMicrophoneProcessing(withFps: 20)
        
        audio.play()
        // Repeat FPS Times / Second Using Timer Class
        _ = Timer.scheduledTimer(withTimeInterval: 1.0 / 20.0, repeats: true) { [weak self] (withFpsTimer) in
            self?.runOnInterval()
        }
       
        //Timer.scheduledTimer(timeInterval: 1.0/20.0, target: self, selector: #selector(runOnInterval), userInfo: nil, repeats: true)
        
        _ = Timer.scheduledTimer(withTimeInterval: 1.0/20.0, repeats: true) { [weak self] (updateViewTimer) in
            self?.updateView()
        }
    }
    
    // Function that runs the same times as the audio manager to update the labels
    @objc func runOnInterval(){
        
        if audio.isLoudSound(cutoff: 1.0) {
            audio.calcLoudestSounds(windowSize: 3)
            audio.determineVowel();
        }
        label1.text = "First Loudest: \(audio.peak1Freq)"
        label2.text = "Second Loudest: \(audio.peak2Freq)"
        vowelSound.text = audio.result;
        
    }
    
    
    @objc func updateView() {
        self.graph?.updateGraph(
            data: self.audio.frozenFftData,
            forKey: "fft"
        )
        self.graph?.updateGraph(
            data: self.audio.frozenTimeData,
            forKey: "time"
        )
        self.graph?.updateGraph(
            data: self.audio.timeData,
            forKey: "timeUnfrozen"
        )
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        audio.pause()
    }
    
}
