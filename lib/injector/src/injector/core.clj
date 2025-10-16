(ns injector.core
  (:require [clojure.edn :as edn]))

(defn- replace-deps
  "Return a function that swaps every dependency entry with a :local/root map.

  The injector passes a map of library symbols to paths.  tools.deps expects
  :local/root entries for dependencies that should resolve from the local
  filesystem, so we wrap every provided path accordingly when the returned
  function is invoked."
  [inj-deps]
  (fn [deps]
    (reduce (fn [m [k v]] (assoc m k {:local/root v})) deps inj-deps)))

(defn- map-vals
  "Apply `f` to every key/value pair and rebuild the map with transformed values."
  [f m]
  (into {} (map (fn [[k v]] [k (f [k v])])) m))

(defn- recursive-update-key
  "Walk nested maps updating the first occurrence of `key` using `f`.

  deps.edn files frequently nest :deps entries (for aliases, for example).
  This helper lets us traverse arbitrarily nested structures to replace the
  dependency map wherever it appears."
  [m key f]
  (map-vals (fn [[k v]]
              (cond (= k key) (f v)
                    (map? v)  (recursive-update-key v key f)
                    :else     v))
            m))

(defn inject-dependencies
  "Inject :local/root overrides for dependencies into a deps.edn structure."
  [deps inj-deps]
  (recursive-update-key deps :deps (replace-deps inj-deps)))
