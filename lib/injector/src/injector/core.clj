(ns injector.core
  "Core logic for injecting :local/root dependencies into deps.edn files.

  This tool solves a key problem when using Clojure with Nix: tools.deps
  expects dependencies to come from Maven repositories, but in Nix builds
  we want to use pre-built JARs from the Nix store.

  The solution is to replace Maven dependency entries like:
    {org.myorg/my-lib {:mvn/version \"1.0.0\"}}

  With :local/root entries pointing to the Nix store:
    {org.myorg/my-lib {:local/root \"/nix/store/xxx-my-lib.jar\"}}

  This allows tools.deps to resolve the dependency from the local filesystem
  instead of trying to download it from Maven Central."
  (:require [clojure.edn :as edn]))

(defn- replace-deps
  "Create a function that replaces dependency entries with :local/root paths.

  Given a map of {library-symbol -> local-path}, returns a function that
  transforms a deps map by wrapping each matching dependency with :local/root.

  Example:
    (def replacer (replace-deps {'org.myorg/my-lib \"/nix/store/xxx.jar\"}))
    (replacer {'org.myorg/my-lib {:mvn/version \"1.0.0\"}})
    ;; => {'org.myorg/my-lib {:local/root \"/nix/store/xxx.jar\"}}"
  [inj-deps]
  (fn [deps]
    (reduce (fn [m [k v]] (assoc m k {:local/root v})) deps inj-deps)))

(defn- map-vals
  "Apply f to each [key value] pair in map m, rebuilding with transformed values.

  Unlike clojure.core/update-vals, this passes both key and value to f,
  which is needed for recursive-update-key to know when it found the target key."
  [f m]
  (into {} (map (fn [[k v]] [k (f [k v])])) m))

(defn- recursive-update-key
  "Recursively walk a nested map, applying f to the value of any key matching `key`.

  deps.edn files can have :deps entries at multiple levels:
  - Top-level :deps for main dependencies
  - :deps within :aliases for alias-specific dependencies
  - Potentially deeper nesting in complex configurations

  This function traverses the entire structure, finding and transforming
  all :deps maps regardless of nesting depth.

  Note: This updates ALL occurrences of the key, not just the first one.
  For deps.edn injection, this is the desired behavior since we want
  local overrides to apply everywhere the dependency is referenced."
  [m key f]
  (map-vals (fn [[k v]]
              (cond
                ;; Found the target key - apply the transformation
                (= k key) (f v)
                ;; Found a nested map - recurse into it
                (map? v)  (recursive-update-key v key f)
                ;; Leaf value - pass through unchanged
                :else     v))
            m))

(defn inject-dependencies
  "Inject :local/root overrides into a deps.edn structure.

  Parameters:
    deps     - Parsed deps.edn as a Clojure map
    inj-deps - Map of {library-symbol -> local-jar-path} to inject

  Returns the modified deps.edn structure with all matching dependencies
  replaced with :local/root entries.

  Example:
    (inject-dependencies
      {:deps {'org.clojure/clojure {:mvn/version \"1.11.1\"}
              'my.org/my-lib {:mvn/version \"1.0.0\"}}}
      {'my.org/my-lib \"/nix/store/xxx-my-lib.jar\"})

    ;; => {:deps {'org.clojure/clojure {:mvn/version \"1.11.1\"}
    ;;            'my.org/my-lib {:local/root \"/nix/store/xxx-my-lib.jar\"}}}"
  [deps inj-deps]
  (recursive-update-key deps :deps (replace-deps inj-deps)))
