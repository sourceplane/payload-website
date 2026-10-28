import PageTemplate, { generateMetadata } from './[slug]/page'

export default PageTemplate

export { generateMetadata }

// Rendered per request from D1, like every page here: the build reads no data.
export const dynamic = 'force-dynamic'
