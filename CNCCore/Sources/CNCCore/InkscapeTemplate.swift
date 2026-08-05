import Foundation

/// TA-4 workspace SVG for Inkscape (mm page, bed outline).
public enum InkscapeTemplate {
    public static func workspaceSVG(profile: MachineProfile = .ta4) -> String {
        let w = profile.travelX
        let h = profile.travelY
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="no"?>
        <!-- Quill Inkscape template: \(Int(w))×\(Int(h)) mm, origin bottom-left on machine -->
        <svg xmlns="http://www.w3.org/2000/svg"
             xmlns:inkscape="http://www.inkscape.org/namespaces/inkscape"
             width="\(fmt(w))mm" height="\(fmt(h))mm"
             viewBox="0 0 \(fmt(w)) \(fmt(h))"
             version="1.1">
          <g inkscape:label="Bed" inkscape:groupmode="layer" id="layer-bed">
            <rect x="0" y="0" width="\(fmt(w))" height="\(fmt(h))"
                  fill="none" stroke="#cccccc" stroke-width="0.5"/>
          </g>
          <g inkscape:label="Pen1" inkscape:groupmode="layer" id="layer-pen1"
             style="display:inline">
            <!-- Draw paths here. Use Path → Object to Path before exporting. -->
          </g>
          <g inkscape:label="Pen2" inkscape:groupmode="layer" id="layer-pen2"
             style="display:inline">
            <!-- Optional second pen / color layer -->
          </g>
        </svg>
        """
    }

    private static func fmt(_ v: Double) -> String {
        String(format: "%.3f", v)
    }
}
