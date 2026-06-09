# EyeFlow

URL: https://eyeflow.org/

EyeFlow is a software used to extract biomarkers from videos created by HoloDoppler. It process determines the Blood Flow Rate, the Velocity, or the Arterial Resistivity Index of the blood vessel in the eye of a patient with the help of an automatic segmentation of the arteries and veins.

## Problem It Solves

EyeFlow transforms complex video data into readable and useful biomarkers, making it accessible for the healthcare professionals.

## Target Audience

The primary users of EyeFlow are:
- Optometrists
- Ophthalmologists
- Scientific researchers

## Key Features

- **GIF Creation**: Generates GIFs representing the analyzed data.
- **Figure Creation**: Produces figures for visual representation of biomarkers.
- **Text File Outputs**: Provides text files listing the extracted biomarkers.

## Installation

To install EyeFlow, follow these steps:

1. Download the ZIP file from the GitHub repository.
2. Extract the contents of the ZIP file. This will include a folder with MATLAB scripts and a MATLAB application.

## Dependencies & Requirements

- A valid MATLAB license is required to run EyeFlow.
- A very performant computer is required to run EyeFlow. 
- Curve Fitting Toolbox
- Deep Learning Toolbox
- Image Processing Toolbox
- MATLAB
- Optimization Toolbox
- Parallel Computing Toolbox
- Signal Processing Toolbox
- Statistics and Machine Learning Toolbox
- Wavelet Toolbox
- Run Matlab, then in "Add-Ons/Explore Add-Ons": search and install the "Deep Learning Toolbox Converter for ONNX Model Format"

## Pytorch models

To use the best models, you must have Python (3.10 - 3.12) and Torch installed.
Python : [Download](https://www.python.org/downloads/release/python-31213/)
Pytorch : 
```bash
pip3 install torch torchvision --index-url https://download.pytorch.org/whl/cu126
```
Make sure that the downloaded Python version is at the top of your user Path.

## Getting Started

To get started with EyeFlow:

1. Refer to the [EyeFlow](https://docs.google.com/presentation/d/1s_adHm5oobDZZIPbrML8hR2-7wbIwT1kt3YC3EdAgYQ/edit#slide=id.g253c1ee4169_0_11) Google Slides presentation for detailed instructions. You can request help from the Digital Holography team for this presentation if needed.

## Contributing

We welcome contributions to EyeFlow. If you are interested in contributing, please follow these guidelines:

1. Fork the repository.
2. Create a new branch (`git checkout -b feature-branch`).
3. Make your changes.
4. Submit a pull request.

## License

EyeFlow is licensed under the GNU General Public License (GPL). See the LICENSE file for more information.

---

Thank you for using Eyeflow!
