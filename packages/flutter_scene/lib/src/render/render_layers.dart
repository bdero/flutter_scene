/// The default layer a [Node] occupies (bit 0).
///
/// A node's `layers` is a 32-bit bitmask; a render view renders the node
/// only when the node's layers intersect the view's layer mask. This lets a
/// view (a capture, a minimap, an editor overlay) include or exclude
/// specific nodes.
const int kRenderLayerDefault = 1;

/// A layer mask that selects every layer (the default render-view mask).
const int kRenderLayerAll = 0xFFFFFFFF;
