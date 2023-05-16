(ns injector.core
  (:require [clojure.edn :as edn]))

(defn- replace-deps [inj-deps]
  (fn [deps] (reduce (fn [m [k v]] (assoc m k { :local/root v})) deps inj-deps)))

(defn- map-vals [f m]
  (into {} (map (fn [[k v]] [k (f [k v])])) m))

(defn- recursive-update-key [m key f]
  (map-vals (fn [[k v]]
              (cond (= k key) (f v)
                    (map? v)  (recursive-update-key v key f)
                    :else     v))
            m))

(defn inject-dependencies [deps inj-deps]
  (recursive-update-key deps :deps (replace-deps inj-deps)))
