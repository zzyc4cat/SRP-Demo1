using System.Collections.Generic;
using UnityEngine;

namespace Grass.Script
{
    [ExecuteInEditMode]
    public class GetPlayerPos : MonoBehaviour
    {
        private const int MaxPlayers = 100;

        private GrassCollider[] _cols;
        private readonly List<Vector4> _poss = new List<Vector4>();
        private readonly Vector4[] _playersBuffer = new Vector4[MaxPlayers];

        public Material material;

        void OnEnable()
        {
            RefreshColliders();
        }

        void Start()
        {
            RefreshColliders();
        }

        void Update()
        {
            if (material == null)
                return;

            if (_cols == null || _cols.Length == 0)
                RefreshColliders();

            _poss.Clear();
            if (_cols != null)
            {
                foreach (var col in _cols)
                {
                    if (col == null)
                        continue;
                    _poss.Add(new Vector4(col.Position.x, col.Position.y, col.Position.z, col.radius));
                }
            }

            for (int i = 0; i < MaxPlayers; i++)
                _playersBuffer[i] = i < _poss.Count ? _poss[i] : Vector4.zero;

            material.SetVectorArray("_Players", _playersBuffer);
        }

        void RefreshColliders()
        {
            _cols = FindObjectsOfType<GrassCollider>();
        }
    }
}
