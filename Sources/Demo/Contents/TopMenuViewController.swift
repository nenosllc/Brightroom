
import AsyncDisplayKit
import GlossButtonNode
import TextureSwiftSupport
import UIKit

final class TopMenuViewController: StackScrollNodeViewController {
    
  override init() {
    super.init()
    title = "Brightroom"
    navigationItem.largeTitleDisplayMode = .always
  }

  override func viewDidLoad() {
    
    super.viewDidLoad()
    
    stackScrollNode.append(nodes: [
      Components.makeSelectionCell(title: "Built-in UI : Crop", onTap: { [unowned self] in
        
        let menu = DemoCropMenuViewController()
        self.navigationController?.pushViewController(menu, animated: true)
        
      }),
      
      Components.makeSelectionCell(title: "Components: Masking", onTap: { [unowned self] in
        
        let menu = DemoMaskingViewController()
        self.navigationController?.pushViewController(menu, animated: true)
        
      }),
      
      Components.makeSelectionCell(title: "Components: Preview", onTap: { [unowned self] in
        let menu = DemoPreviewViewController()
        self.navigationController?.pushViewController(menu, animated: true)
      }),
      
      Components.makeSelectionCell(title: "Components: MetalImageView", onTap: { [unowned self] in
        // TODO:
      }),
      
      Components.makeSelectionCell(title: "CIKernel", onTap: { [unowned self] in
        
        let menu = DemoCIKernelViewController()
        self.navigationController?.pushViewController(menu, animated: true)
        
      }),
      
      Components.makeSelectionCell(title: "Editor", onTap: { [unowned self] in
        
        let menu = DemoBuiltInEditorViewController()
        self.navigationController?.pushViewController(menu, animated: true)
        
      }),
    ])
    

  }

}
