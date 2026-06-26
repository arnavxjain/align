import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private var sharedUrl: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.031, green: 0.031, blue: 0.031, alpha: 0.01)
        extractSharedUrl { [weak self] url in
            DispatchQueue.main.async {
                self?.sharedUrl = url
                self?.buildUI(url: url)
            }
        }
    }

    // MARK: - URL extraction

    private func extractSharedUrl(completion: @escaping (String?) -> Void) {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else {
            completion(nil)
            return
        }

        let urlType = UTType.url.identifier
        let textType = UTType.plainText.identifier

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(urlType) {
                provider.loadItem(forTypeIdentifier: urlType, options: nil) { data, _ in
                    let url = (data as? URL)?.absoluteString ?? (data as? String)
                    completion(url)
                }
                return
            }
        }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(textType) {
                provider.loadItem(forTypeIdentifier: textType, options: nil) { data, _ in
                    let text = data as? String
                    let isUrl = text.flatMap { URL(string: $0) }.map {
                        $0.scheme == "http" || $0.scheme == "https"
                    } ?? false
                    completion(isUrl ? text : nil)
                }
                return
            }
        }

        completion(nil)
    }

    // MARK: - UI

    private func buildUI(url: String?) {
        let logoLabel = UILabel()
        logoLabel.text = "Align"
        logoLabel.font = UIFont.systemFont(ofSize: 22, weight: .bold)
        logoLabel.textColor = .white
        logoLabel.textAlignment = .center

        let titleLabel = UILabel()
        titleLabel.text = "Add to Align"
        titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.textAlignment = .center

        let urlLabel = UILabel()
        urlLabel.text = url ?? "No URL found"
        urlLabel.font = UIFont.systemFont(ofSize: 13)
        urlLabel.textColor = UIColor.white.withAlphaComponent(0.45)
        urlLabel.textAlignment = .center
        urlLabel.numberOfLines = 2
        urlLabel.lineBreakMode = .byTruncatingMiddle

        let openButton = UIButton(type: .system)
        openButton.setTitle(url != nil ? "Open in Align" : "Close", for: .normal)
        openButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: .semibold)
        openButton.setTitleColor(.white, for: .normal)
        openButton.backgroundColor = UIColor(red: 0.0, green: 0.478, blue: 1.0, alpha: 1.0)
        openButton.layer.cornerRadius = 14
        openButton.layer.cornerCurve = .continuous
        openButton.addTarget(self, action: #selector(openTapped), for: .touchUpInside)

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.titleLabel?.font = UIFont.systemFont(ofSize: 16)
        cancelButton.setTitleColor(UIColor.white.withAlphaComponent(0.55), for: .normal)
        cancelButton.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)

        let card = UIView()
        card.backgroundColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 0.98)
        card.layer.cornerRadius = 24
        card.layer.cornerCurve = .continuous
        card.layer.borderWidth = 0.8
        card.layer.borderColor = UIColor.white.withAlphaComponent(0.12).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false

        [logoLabel, titleLabel, urlLabel, openButton, cancelButton].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview($0)
        }
        view.addSubview(card)

        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            card.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -8),

            logoLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 28),
            logoLabel.centerXAnchor.constraint(equalTo: card.centerXAnchor),

            titleLabel.topAnchor.constraint(equalTo: logoLabel.bottomAnchor, constant: 12),
            titleLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            urlLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            urlLabel.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            urlLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),

            openButton.topAnchor.constraint(equalTo: urlLabel.bottomAnchor, constant: 24),
            openButton.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            openButton.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            openButton.heightAnchor.constraint(equalToConstant: 56),

            cancelButton.topAnchor.constraint(equalTo: openButton.bottomAnchor, constant: 10),
            cancelButton.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            cancelButton.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
        ])
    }

    // MARK: - Actions

    @objc private func openTapped() {
        guard let urlString = sharedUrl,
              let encoded = urlString.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let deepLink = URL(string: "align://new?url=\(encoded)") else {
            extensionContext?.completeRequest(returningItems: nil)
            return
        }

        var responder: UIResponder? = self
        while responder != nil {
            if let app = responder as? UIApplication {
                app.open(deepLink)
                break
            }
            responder = responder?.next
        }

        extensionContext?.completeRequest(returningItems: nil)
    }

    @objc private func cancelTapped() {
        extensionContext?.completeRequest(returningItems: nil)
    }
}
