import { useState, useEffect } from 'react'

const API = 'http://localhost:8000'

function App() {
  const [fruits, setFruits] = useState([])
  const [filters, setFilters] = useState(() => {
    const p = new URLSearchParams(window.location.search)
    return { name: p.get('name') || '', color: p.get('color') || '', in_season: p.get('in_season') || '' }
  })

  useEffect(() => {
    const qs = new URLSearchParams()
    if (filters.name) qs.set('name', filters.name)
    if (filters.color) qs.set('color', filters.color)
    if (filters.in_season !== '') qs.set('in_season', filters.in_season)
    window.history.replaceState(null, '', `?${qs}`)
    fetch(`${API}/fruit?${qs}`)
      .then(r => r.json())
      .then(setFruits)
      .catch(console.error)
  }, [filters])

  const update = (k, v) => setFilters(f => ({ ...f, [k]: v }))

  return (
    <div>
      <h1>Fruit List</h1>
      <div>
        <label>Name: <input value={filters.name} onChange={e => update('name', e.target.value)} /></label>
        {' '}
        <label>Color: <input value={filters.color} onChange={e => update('color', e.target.value)} /></label>
        {' '}
        <label>In Season:
          <select value={filters.in_season} onChange={e => update('in_season', e.target.value)}>
            <option value="">All</option>
            <option value="true">Yes</option>
            <option value="false">No</option>
          </select>
        </label>
      </div>
      <ul>
        {fruits.map(f => (
          <li key={f.name}>
            <strong>{f.name}</strong> — {f.color} — {f.in_season ? 'In Season' : 'Out of Season'}
          </li>
        ))}
      </ul>
      {fruits.length === 0 && <p>No fruit found.</p>}
    </div>
  )
}

export default App
