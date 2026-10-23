// The app's name: this repository's name. Frontier names everything after it, so
// it decides where each environment deploys and which namespace bin/create-secret
// seals for:
//   - the frontier-<name> ArgoCD project and the frontier-<name>-dev and
//     frontier-<name>-prod namespaces it allows
//   - the image, ghcr.io/persona-id/<name>
//
// Frontier sets it when it generates the repo from persona-template-frontier-app.
// CI fails if it doesn't match the repository's name. Change it only when renaming
// the repository, and register the new name in frontier-app-registry.
{
  name: 'persona-template-frontier-app',

  repoURL: 'https://github.com/persona-id/' + self.name,
  imageRepository: 'ghcr.io/persona-id/' + self.name,
}
