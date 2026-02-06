import CoreAudioKit
import SwiftUI
import AudioToolbox

/// AUViewController for M2DX Audio Unit Extension
public class M2DXAudioUnitViewController: AUViewController {

    // MARK: - Properties

    private var parameterTree: AUParameterTree?
    private var hostingController: UIHostingController<AUEditorView>?

    // MARK: - AUViewController

    public override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor.systemBackground

        // Set preferred content size for AU host
        preferredContentSize = CGSize(width: 800, height: 600)

        // Setup empty UI initially - will be updated when audio unit is set
        setupUI()
    }

    // MARK: - UI Setup

    public func configure(with audioUnit: AUAudioUnit) {
        self.parameterTree = audioUnit.parameterTree
        DispatchQueue.main.async { [weak self] in
            self?.setupUI()
        }
    }

    private func setupUI() {
        // Remove existing hosting controller if any
        hostingController?.willMove(toParent: nil)
        hostingController?.view.removeFromSuperview()
        hostingController?.removeFromParent()

        // Create SwiftUI view with parameter tree binding
        let editorView = AUEditorView(parameterTree: parameterTree)

        // Host SwiftUI view
        let hosting = UIHostingController(rootView: editorView)
        addChild(hosting)
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting.view)

        NSLayoutConstraint.activate([
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])

        hosting.didMove(toParent: self)
        hostingController = hosting
    }
}

// MARK: - SwiftUI Editor View

/// Main SwiftUI view for Audio Unit editor
struct AUEditorView: View {
    let parameterTree: AUParameterTree?

    @State private var algorithm: Float = 0
    @State private var masterVolume: Float = 0.7
    @State private var operatorLevels: [Float] = Array(repeating: 1.0, count: 6)
    @State private var operatorRatios: [Float] = [1, 2, 3, 4, 5, 6]

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                headerSection

                // Global Controls
                globalControlsSection

                // Operator Grid (2x3, DX7 compatible)
                operatorGridSection
            }
            .padding()
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            loadParameterValues()
        }
    }

    private var headerSection: some View {
        HStack {
            Image(systemName: "waveform")
                .font(.largeTitle)
                .foregroundColor(.cyan)

            VStack(alignment: .leading) {
                Text("M2DX")
                    .font(.title)
                    .fontWeight(.bold)

                Text("6-Operator FM Synthesizer")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private var globalControlsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Global")
                .font(.headline)

            HStack(spacing: 20) {
                // Algorithm selector
                VStack {
                    Text("Algorithm")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Picker("Algorithm", selection: Binding(
                        get: { Int(algorithm) },
                        set: { newValue in
                            algorithm = Float(newValue)
                            setParameter(address: 0, value: algorithm) // algorithm address
                        }
                    )) {
                        ForEach(1...32, id: \.self) { num in
                            Text("\(num)").tag(num - 1)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 100)
                }

                // Master volume
                VStack {
                    Text("Volume")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Slider(value: Binding(
                        get: { masterVolume },
                        set: { newValue in
                            masterVolume = newValue
                            setParameter(address: 1, value: newValue) // masterVolume address
                        }
                    ), in: 0...1)
                    .frame(width: 150)

                    Text("\(Int(masterVolume * 100))%")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.secondarySystemBackground))
        )
    }

    private var operatorGridSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Operators")
                .font(.headline)

            // 2x3 grid (DX7 compatible: 6 operators)
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                ForEach(0..<6, id: \.self) { index in
                    operatorCard(index: index)
                }
            }
        }
    }

    private func operatorCard(index: Int) -> some View {
        VStack(spacing: 8) {
            // Operator header
            HStack {
                Circle()
                    .fill(operatorColor(index: index))
                    .frame(width: 12, height: 12)

                Text("OP\(index + 1)")
                    .font(.headline)
                    .fontWeight(.semibold)

                Spacer()
            }

            // Level slider
            VStack(alignment: .leading, spacing: 4) {
                Text("Level")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { operatorLevels[index] },
                    set: { newValue in
                        operatorLevels[index] = newValue
                        setOperatorParameter(index: index, offset: 0, value: newValue)
                    }
                ), in: 0...1)
            }

            // Ratio display
            VStack(alignment: .leading, spacing: 4) {
                Text("Ratio")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Slider(value: Binding(
                    get: { operatorRatios[index] },
                    set: { newValue in
                        operatorRatios[index] = newValue
                        setOperatorParameter(index: index, offset: 1, value: newValue)
                    }
                ), in: 0.5...16)

                Text(String(format: "%.2f", operatorRatios[index]))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.tertiarySystemBackground))
        )
    }

    private func operatorColor(index: Int) -> Color {
        let colors: [Color] = [
            .red, .orange, .yellow, .green,
            .cyan, .blue, .purple, .pink
        ]
        return colors[index % colors.count]
    }

    // MARK: - Parameter Handling

    private func loadParameterValues() {
        guard let tree = parameterTree else { return }

        // Global parameters - using address constants from M2DXParameterAddress
        if let param = tree.parameter(withAddress: 0) { // algorithm
            algorithm = param.value
        }
        if let param = tree.parameter(withAddress: 1) { // masterVolume
            masterVolume = param.value
        }

        // Operator parameters - using calculated addresses
        for i in 0..<6 {
            let levelAddress = AUParameterAddress(100 + i * 100 + 0) // operatorBase + stride + levelOffset
            let ratioAddress = AUParameterAddress(100 + i * 100 + 1) // operatorBase + stride + ratioOffset

            if let levelParam = tree.parameter(withAddress: levelAddress) {
                operatorLevels[i] = levelParam.value
            }
            if let ratioParam = tree.parameter(withAddress: ratioAddress) {
                operatorRatios[i] = ratioParam.value
            }
        }
    }

    private func setParameter(address: UInt64, value: Float) {
        parameterTree?.parameter(withAddress: AUParameterAddress(address))?.value = value
    }

    private func setOperatorParameter(index: Int, offset: Int, value: Float) {
        // Calculate operator parameter address using the same structure as M2DXParameterAddress
        // operatorBase (100) + index * operatorStride (100) + offset
        let address = AUParameterAddress(100 + index * 100 + offset)
        parameterTree?.parameter(withAddress: address)?.value = value
    }
}

#Preview {
    AUEditorView(parameterTree: nil)
}
